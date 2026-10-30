import Foundation
import Combine
import AppKit
import UserNotifications

/// Lets AppState pin the popover *synchronously* around modal alerts / operations
/// (notifications hop through the run loop — too late for `NSAlert.runModal`).
@MainActor
protocol PopoverHost: AnyObject {
    func setModalDepth(_ delta: Int)
    func refreshPin()
}

@MainActor
final class AppState: ObservableObject {
    /// Latest raw sample (not published — avoids double UI refresh with displayMetrics).
    private(set) var rawMetrics = SystemMetrics.zero
    @Published var displayMetrics = SystemMetrics.zero
    @Published var isTurboActive = false
    @Published var isOptimizing = false
    /// Short status shown in the busy banner while an action runs.
    @Published var operationStatus: String?
    @Published var operationDetail: String?
    @Published var cleaningBucket: StorageBucket?
    @Published var lastCleanResult: CleanResult?
    @Published var lastReport: ActionReport?
    @Published var watchdogItems: [WatchdogItem] = []
    @Published var topProcesses: [TopProcess] = []
    @Published var watchdogLastScan: Date = .distantPast
    @Published var watchdogScanning = false
    @Published var turboProgress: String?
    @Published var actionError: String?
    @Published var storageBuckets: [StorageBucketSize] = []
    @Published var storageScanning = false
    @Published var smartRAMSuggestionActive = false

    let sampler = MetricsSampler()
    let smoother = MetricSmoother()
    let watchdog = WatchdogEngine()
    let turbo = TurboModeEngine()
    let cleaner = SystemCleaner()
    let whitelist = WhitelistStore()
    let focus = FocusProfileEngine()
    let network = NetworkPulseMonitor()
    let history = ProcessHistoryStore()
    let storageScanner = StorageMapScanner()
    let reports = ActionReportStore.shared
    let settings = FeatureSettingsStore.shared

    private var cancellables = Set<AnyCancellable>()
    private var isPopoverOpen = false
    private var isRunning = false
    private let thermalObserver = ThermalStateObserver()
    private var lastAuthCancelAt: Date?
    private var didNotifySmartRAM = false
    private var widgetTimer: Timer?
    private var lastWidgetSnapshot: (cpu: Double, ram: UInt64, turbo: Bool)?

    weak var uiHost: PopoverHost?
    /// Set by AppDelegate from the launch Apple event / login time (see runLaunchOptimizeIfNeeded).
    var launchedAsLoginItem = false
    /// Urgent banner snooze after the user taps its action.
    var urgentSnoozedUntil: Date = .distantPast

    private enum Pace {
        /// Popover open — responsive but not frantic.
        static let samplerOpen: TimeInterval = 2.5
        /// Menu-bar only — must stay near-idle (was 5s and still drove SwiftUI redraws).
        static let samplerClosed: TimeInterval = 15.0
        static let samplerAfterAction: TimeInterval = 3.0
        static let samplerBusy: TimeInterval = 10.0
    }

    /// Runs a long action with visible loading state + quieter metrics sampling (stability).
    func runOperation(
        status: String,
        detail: String? = nil,
        bucket: StorageBucket? = nil,
        kickMetricsAfter: Bool = true,
        _ work: @escaping () async -> Void
    ) {
        guard !isOptimizing else { return }
        Task {
            beginOperation(status, detail: detail, bucket: bucket)
            defer { endOperation() }
            await work()
            if kickMetricsAfter, isPopoverOpen {
                sampler.setInterval(Pace.samplerAfterAction)
                sampler.kick()
            }
        }
    }

    private func beginOperation(_ status: String, detail: String?, bucket: StorageBucket?) {
        isOptimizing = true
        operationStatus = status
        operationDetail = detail
        cleaningBucket = bucket
        // A stale result must not sit under the busy banner.
        reports.dismiss()
        sampler.setInterval(Pace.samplerBusy)
        watchdog.setForeground(false)
        uiHost?.refreshPin()
        NotificationCenter.default.post(name: .fgOperationDidStart, object: status)
    }

    private func endOperation() {
        isOptimizing = false
        operationStatus = nil
        operationDetail = nil
        cleaningBucket = nil
        sampler.setInterval(isPopoverOpen ? Pace.samplerOpen : Pace.samplerClosed)
        watchdog.setForeground(isPopoverOpen)
        uiHost?.refreshPin()
        NotificationCenter.default.post(name: .fgOperationDidEnd, object: nil)
    }

    func start() {
        isRunning = true
        smoother.$display
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self else { return }
                if self.displayMetrics.visuallyEqual(to: metrics, epsilon: 0.002),
                   abs(self.displayMetrics.timestamp.timeIntervalSince(metrics.timestamp)) < 2 {
                    return
                }
                self.displayMetrics = metrics
            }
            .store(in: &cancellables)

        sampler.$metrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                guard let self else { return }
                self.rawMetrics = metrics
                // Critical: while popover is closed, do NOT push into MetricSmoother/displayMetrics.
                // NSPopover keeps the SwiftUI tree alive — updating gauges redraws Angular/blur layers offscreen (~25% CPU).
                if self.isPopoverOpen {
                    self.smoother.updateTarget(metrics)
                }
                self.evaluateSmartRAM(metrics)
            }
            .store(in: &cancellables)

        reports.$latest
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastReport)

        watchdog.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self, self.isPopoverOpen else { return }
                self.watchdogItems = items
            }
            .store(in: &cancellables)

        watchdog.$topProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tops in
                guard let self else { return }
                // History always; UI publish only while popover open.
                self.history.record(top: tops, paused: self.settings.historyCollectionPaused)
                if self.isPopoverOpen {
                    self.topProcesses = tops
                }
            }
            .store(in: &cancellables)

        watchdog.$lastScanAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] at in
                guard let self, self.isPopoverOpen else { return }
                self.watchdogLastScan = at
            }
            .store(in: &cancellables)

        watchdog.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanning in
                guard let self, self.isPopoverOpen else { return }
                self.watchdogScanning = scanning
            }
            .store(in: &cancellables)

        turbo.$isActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTurboActive)

        turbo.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$turboProgress)

        sampler.start(interval: Pace.samplerClosed)
        // Network sampling only while popover is open (netstat/nettop were hot in samples).
        Task { await turbo.syncFromSystem() }
        SharedMetricsSnapshot.write(from: displayMetrics, turbo: isTurboActive)

        thermalObserver.start { [weak self] level in
            guard let self else { return }
            var m = self.rawMetrics
            guard m.thermalLevel != level else { return }
            m.thermalLevel = level
            m.timestamp = Date()
            self.rawMetrics = m
            if self.isPopoverOpen {
                self.smoother.updateTarget(m)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isRunning else { return }
            self.watchdog.start(whitelist: self.whitelist, sampler: self.sampler)
            self.watchdog.setForeground(self.isPopoverOpen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runLaunchOptimizeIfNeeded()
        }

        // Widget snapshot — raw metrics, 60 s with tolerance, and only when something moved
        // (the widget itself refreshes every 5 min).
        let widget = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.writeWidgetSnapshotIfChanged() }
        }
        widget.tolerance = 15
        RunLoop.main.add(widget, forMode: .common)
        widgetTimer = widget
    }

    private func writeWidgetSnapshotIfChanged() {
        let m = rawMetrics
        guard m.timestamp > .distantPast else { return }
        if let last = lastWidgetSnapshot,
           last.turbo == isTurboActive,
           abs(last.cpu - m.cpuUsageFraction) < 0.01,
           abs(Int64(last.ram) - Int64(m.memoryAvailableBytes)) < 100 * 1024 * 1024 {
            return
        }
        lastWidgetSnapshot = (m.cpuUsageFraction, m.memoryAvailableBytes, isTurboActive)
        SharedMetricsSnapshot.write(from: m, turbo: isTurboActive)
    }

    func stop() {
        isRunning = false
        sampler.stop()
        smoother.stop()
        watchdog.stop()
        network.stop()
        thermalObserver.stop()
        widgetTimer?.invalidate()
        widgetTimer = nil
        history.flush(sync: true)
        // Never mdutil -a -i on at quit — that caused Spotlight reindex storms.
        turbo.detachWithoutRestoringSpotlight()
    }

    func popoverDidOpen() {
        isPopoverOpen = true
        sampler.setInterval(Pace.samplerOpen)
        smoother.start()
        smoother.snap(to: rawMetrics)
        displayMetrics = rawMetrics
        // Flush latest watchdog snapshot into UI now that we're visible.
        topProcesses = watchdog.topProcesses
        watchdogItems = watchdog.items
        watchdogLastScan = watchdog.lastScanAt
        sampler.kick()
        watchdog.setForeground(true)
        network.start(interval: 4.0)
        network.kick()
        history.recompute()
        SessionAuth.shared.setCountdownVisible(true)
        // `mdutil -s /` runs off-main; the UI picks up the result when it lands.
        turbo.refreshIndexingStatusInBackground()
        if turbo.indexingDisabledVerified != isTurboActive {
            if turbo.indexingDisabledVerified {
                isTurboActive = true
            }
        }
    }

    func popoverDidClose() {
        isPopoverOpen = false
        sampler.setInterval(Pace.samplerClosed)
        smoother.stop()
        network.stop()
        watchdog.setForeground(false)
        SessionAuth.shared.setCountdownVisible(false)
    }

    /// "Optimize after startup" — only on a real login launch of the resident agent.
    /// A manual open is not a login: on-demand users would otherwise get their Time Machine
    /// backup stopped every time they click the icon.
    private func runLaunchOptimizeIfNeeded() {
        let launch = LaunchAtLoginStore.shared
        guard launch.optimizeOnLaunch else { return }
        guard launchedAsLoginItem, launch.isEnabled, settings.keepInMenuBar else {
            AppLog.lifeFile("launch optimize skipped (loginLaunch=\(launchedAsLoginItem) loginItem=\(launch.isEnabled) resident=\(settings.keepInMenuBar))")
            return
        }
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("--open-cleaner"), !PermissionManager.shared.shouldReopenCleanerAfterRelaunch else { return }
        Task {
            // Pause a backup only if one is actually running; keep heavy folders out of Spotlight.
            let tmPaused = await TimeMachineStatus.stopBackupIfRunning()
            let excluded = await turbo.ensureHeavyExclusions()
            AppLog.lifeFile("launch optimize: tmPaused=\(tmPaused) exclusions=\(excluded)")

            // At most once per calendar day: wipe safe caches + stale logs (no admin).
            let dayKey = "fg.launch.lastLightBoostDay"
            let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            let last = UserDefaults.standard.double(forKey: dayKey)
            guard today > last else {
                AppLog.lifeFile("launch optimize: exclusions=\(excluded) (caches skipped, already today)")
                return
            }
            UserDefaults.standard.set(today, forKey: dayKey)
            let result = await cleaner.runLaunchLightBoost()
            AppLog.lifeFile(
                "launch light boost: excluded=\(excluded) caches=\(result.cacheBytesFreed) logs=\(result.logsBytesFreed) tm=\(result.timeMachineStopped)"
            )
        }
    }

    /// Primary “make my Mac snappier” action — caches, logs, DNS, TM pause, exclusions, optional purge.
    func speedBoost() {
        let confirmed = confirm(
            title: "Quick Optimize?",
            message: "One-shot tune-up (not the same as Turbo Mode):\n\n• Clear safe regenerable caches\n• Remove stale logs (14+ days)\n• Pause a Time Machine backup if one is running\n• Keep heavy cache folders out of Spotlight\n• Flush DNS + free reclaimable RAM (admin once)\n\nTurbo Mode is separate — it stays on to keep Spotlight off heavy folders.\n\nDoes not quit your apps, touch Docker, or wipe Derived Data."
        )
        guard confirmed else { return }

        runOperation(status: "Quick Optimize…", detail: "Caches → logs → Spotlight → DNS → RAM") {
            self.operationDetail = "Clearing caches & stale logs…"
            var result = await self.cleaner.runSpeedBoost(purgeMemory: true)
            self.operationDetail = "Excluding heavy folders from Spotlight…"
            result.spotlightExcluded = await self.turbo.ensureHeavyExclusions()
            self.lastCleanResult = result
            self.publishReport(ActionReport.fromCleanResult(result, title: "Quick Optimize"))
            // Storage sizes refresh in the background — the tune-up is already done.
            if self.isPopoverOpen { self.refreshStorageMap() }
        }
    }

    /// Sticky by default (stays until dismissed / next action); minor actions can fade.
    private func publishReport(_ report: ActionReport, transient: Bool = false) {
        reports.publish(report, autoClearAfter: transient ? ActionReportStore.transientSeconds : nil)
    }

    // MARK: - Smart RAM

    private func evaluateSmartRAM(_ metrics: SystemMetrics) {
        let critical = metrics.memoryPressure >= .critical
        let warn = metrics.memoryPressure >= .warning
        if smartRAMSuggestionActive != warn {
            smartRAMSuggestionActive = warn
        }

        guard critical else {
            didNotifySmartRAM = false
            return
        }

        if !didNotifySmartRAM {
            didNotifySmartRAM = true
            Task { await notifySmartRAMSuggestion() }
        }

        guard settings.canAutoFreeRAMNow() else { return }
        if let cancel = lastAuthCancelAt, Date().timeIntervalSince(cancel) < 120 { return }
        if !SessionAuth.shared.isSessionValid {
            // Don't auto-prompt password loops — only auto when already unlocked.
            return
        }
        settings.markAutoFreeRAM()
        AppLog.lifeFile("SmartRAM auto purge")
        freeRAM(skipConfirm: true, fromSmartSuggest: true)
    }

    private func notifySmartRAMSuggestion() async {
        let ok = await PermissionManager.shared.requestNotificationsIfNeeded()
        guard ok else { return }
        let content = UNMutableNotificationContent()
        content.title = "Memory pressure high"
        content.body = "Tap the menu bar icon → Free RAM now, or enable Auto Free RAM."
        content.sound = .default
        content.categoryIdentifier = NotificationCategories.smartRAMCategoryID
        let req = UNNotificationRequest(identifier: "fg.smart.ram", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Actions

    func toggleTurbo() {
        if isTurboActive {
            runOperation(status: "Turning Turbo off…", detail: "Finishing soft Turbo") {
                let before = self.rawMetrics.memoryAvailableBytes
                await self.turbo.deactivate()
                self.publishReport(ActionReport(
                    title: "Turbo off",
                    availableBefore: before,
                    availableAfter: MachMemory.sample()?.availableBytes ?? before,
                    detail: "Soft Turbo off — Spotlight volume unchanged (no reindex storm)"
                ))
            }
            return
        }

        let clearDD = FeatureSettingsStore.shared.clearDerivedDataOnTurbo
        let ddLine = clearDD
            ? "\n\nAlso clears Xcode Derived Data (you enabled this in Startup settings)."
            : "\n\nDoes NOT clear Xcode Derived Data (enable in Startup settings if you want that)."
        let confirmed = confirm(
            title: "Enable Turbo Mode?",
            message: "Excludes heavy cache folders from Spotlight (Caches, DerivedData, simulators, npm/pnpm caches) and stops Time Machine backups in progress.\n\nVolume-wide Spotlight indexing stays ON — turning Turbo off will NOT trigger a full reindex storm." + ddLine + "\n\nTurbo does NOT free RAM. Use Free RAM for that."
        )
        guard confirmed else { return }

        runOperation(status: "Enabling Turbo…", detail: "Excluding heavy caches · stopping TM backup") {
            let before = self.rawMetrics.memoryAvailableBytes
            let result = await self.turbo.activate(clearDerivedData: clearDD)
            if let error = result.error {
                self.actionError = error
                if error.localizedCaseInsensitiveContains("cancel") {
                    self.lastAuthCancelAt = Date()
                }
            } else {
                self.publishReport(ActionReport(
                    title: "Turbo on",
                    availableBefore: before,
                    availableAfter: MachMemory.sample()?.availableBytes ?? before,
                    detail: "Heavy folders excluded · volume indexing ON"
                ))
            }
        }
    }

    func clearCache() {
        let confirmed = confirm(
            title: "Deep Clean?",
            message: "Clears regenerable caches under ~/Library/Caches, flushes DNS (admin), and prunes unused Docker data if Docker is installed."
        )
        guard confirmed else { return }

        runOperation(status: "Deep cleaning…", detail: "Caches → DNS → Docker. This can take a minute.") {
            let before = self.rawMetrics.memoryAvailableBytes
            self.operationDetail = "Cleaning safe caches…"
            let result = await self.cleaner.runDeepClean()
            self.lastCleanResult = result
            let after = MachMemory.sample()?.availableBytes ?? before
            self.publishReport(ActionReport(
                title: "Deep Clean",
                availableBefore: before,
                availableAfter: after,
                bytesCleaned: result.cacheBytesFreed,
                dnsFlushed: result.dnsFlushed,
                detail: result.summary
            ))
            if self.isPopoverOpen { self.refreshStorageMap() }
        }
    }

    func freeRAM(skipConfirm: Bool = false, fromSmartSuggest: Bool = false) {
        if !skipConfirm {
            let confirmed = confirm(
                title: "Free RAM (purge disk cache)?",
                message: "Runs macOS `purge` (admin password) to drop reclaimable file cache.\n\nApps stay open. Available memory should rise briefly — macOS may refill cache as you work. That is healthy, not a leak."
            )
            guard confirmed else { return }
        }

        runOperation(status: "Freeing RAM…", detail: "Running purge — enter admin if asked") {
            let result = await self.cleaner.purgeInactiveMemory()
            self.lastCleanResult = result
            if !result.memoryPurged {
                self.actionError = "Purge cancelled or failed. Admin permission is required."
                self.lastAuthCancelAt = Date()
            } else {
                self.publishReport(ActionReport.fromCleanResult(
                    result,
                    title: fromSmartSuggest ? "Smart Free RAM" : "Free RAM"
                ))
            }
        }
    }

    func killHogs() {
        let hogs = watchdogItems.filter { $0.kind == .hog }
        guard !hogs.isEmpty else {
            actionError = "No CPU hogs detected right now."
            return
        }
        let names = hogs.map(\.name).joined(separator: ", ")
        let confirmed = confirm(
            title: "Force quit resource hogs?",
            message: "Will quit: \(names)\n\nWhitelisted apps (Cursor, Terminal, Docker, Xcode, …) are never killed."
        )
        guard confirmed else { return }

        runOperation(status: "Quitting CPU hogs…", detail: names) {
            let before = self.rawMetrics.memoryAvailableBytes
            let count = hogs.count
            // Only the hogs the dialog listed — never the merely "elevated" ones.
            await self.watchdog.killAllHogs(whitelist: self.whitelist, kinds: [.hog])
            self.publishReport(ActionReport(
                title: "Kill Hogs",
                availableBefore: before,
                availableAfter: MachMemory.sample()?.availableBytes ?? before,
                processesQuit: count
            ))
        }
    }

    func killItem(_ item: WatchdogItem) {
        if whitelist.isProtected(bundleID: item.bundleID, name: item.name) {
            actionError = "\(item.name) is whitelisted and cannot be killed."
            return
        }
        let confirmed = confirm(
            title: "Force quit \(item.name)?",
            message: "Unsaved work in that app may be lost."
        )
        guard confirmed else { return }

        Task {
            await watchdog.forceKill(item: item)
            publishReport(ActionReport(title: "Quit \(item.name)", processesQuit: 1), transient: true)
        }
    }

    func applyFocus(_ profile: FocusProfile) {
        runOperation(status: "Applying \(profile.title) focus…", detail: "Updating focus profile") {
            let report = await self.focus.apply(
                profile, turbo: self.turbo, watchdog: self.watchdog, whitelist: self.whitelist
            )
            self.publishReport(report)
        }
    }

    func flushDNS() {
        runOperation(status: "Flushing DNS…", detail: "Admin may be required") {
            let result = await self.cleaner.flushDNSOnly()
            self.lastCleanResult = result
            self.publishReport(ActionReport.fromCleanResult(result, title: "DNS flush"), transient: true)
        }
    }

    /// Passive measurement — shows an inline spinner in the Storage card, never the busy banner.
    func refreshStorageMap() {
        guard !storageScanning else { return }
        Task {
            storageScanning = true
            defer { storageScanning = false }
            storageBuckets = await storageScanner.refreshAll()
        }
    }

    func cleanStorageBucket(_ bucket: StorageBucket) {
        if bucket.needsConfirm {
            let confirmed = confirm(
                title: "Clean \(bucket.title)?",
                message: bucket.confirmMessage
            )
            guard confirmed else { return }
        }
        runOperation(
            status: "Cleaning \(bucket.title)…",
            detail: "Working — please wait until this finishes",
            bucket: bucket
        ) {
            let result = await self.cleaner.cleanBucket(bucket)
            self.lastCleanResult = result
            self.publishReport(ActionReport.fromCleanResult(result, title: "Clean \(bucket.title)"))
            self.refreshStorageMap()
        }
    }

    func coolDown() {
        runOperation(status: "Cooling down…", detail: "Quitting hogs & elevated apps · Low Power if on battery") {
            let thermalBefore = self.rawMetrics.thermalLevel
            let before = self.rawMetrics.memoryAvailableBytes
            let targets = self.watchdogItems.filter { $0.kind == .hog || $0.kind == .elevated }
            let count = targets.count
            await self.watchdog.killAllHogs(whitelist: self.whitelist, kinds: [.hog, .elevated])
            let lowPower = await PowerModeHelper.setLowPower(true, onlyOnBattery: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let thermalAfter = ThermalMonitor.sample()
            self.publishReport(ActionReport(
                title: "Cool down",
                availableBefore: before,
                availableAfter: MachMemory.sample()?.availableBytes ?? before,
                processesQuit: count,
                thermalBefore: thermalBefore,
                thermalAfter: thermalAfter,
                lowPowerChanged: lowPower,
                detail: count == 0 && !lowPower ? "Nothing to quit · already cool" : nil
            ))
        }
    }

    func quitLeftovers() {
        runOperation(status: "Quitting leftovers…", detail: "Closing noisy helper apps") {
            var quit = 0
            for app in NSWorkspace.shared.runningApplications {
                let name = app.localizedName ?? ""
                let bid = app.bundleIdentifier
                guard LeftoverApps.matches(bundleID: bid, name: name) else { continue }
                guard self.whitelist.isKillCandidate(bundleID: bid, name: name, runningApp: app) else { continue }
                _ = app.terminate()
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !app.isTerminated { _ = app.forceTerminate() }
                quit += 1
            }
            self.publishReport(ActionReport(title: "Quit leftovers", processesQuit: quit))
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        #if DEBUG
        if DebugAutomation.autoConfirm {
            AppLog.lifeFile("debug autoConfirm: \(title)")
            return true
        }
        #endif
        // Pin the popover so the alert click / app switch can't collapse it (and so the
        // on-demand quit can't fire under a modal).
        uiHost?.setModalDepth(+1)
        defer { uiHost?.setModalDepth(-1) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
