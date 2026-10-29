import Foundation
import Combine
import AppKit
import UserNotifications

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

    private enum Pace {
        static let samplerOpen: TimeInterval = 1.6
        static let samplerClosed: TimeInterval = 5.0
        static let samplerAfterAction: TimeInterval = 2.0
        static let samplerBusy: TimeInterval = 8.0
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
        sampler.setInterval(Pace.samplerBusy)
        watchdog.setForeground(false)
        NotificationCenter.default.post(name: .fgOperationDidStart, object: status)
    }

    private func endOperation() {
        isOptimizing = false
        operationStatus = nil
        operationDetail = nil
        cleaningBucket = nil
        sampler.setInterval(isPopoverOpen ? Pace.samplerOpen : Pace.samplerClosed)
        watchdog.setForeground(isPopoverOpen)
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
                self.smoother.updateTarget(metrics)
                self.evaluateSmartRAM(metrics)
            }
            .store(in: &cancellables)

        reports.$latest
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastReport)

        watchdog.$items
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchdogItems)

        watchdog.$topProcesses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tops in
                guard let self else { return }
                self.topProcesses = tops
                self.history.record(top: tops, paused: self.settings.historyCollectionPaused)
            }
            .store(in: &cancellables)

        watchdog.$lastScanAt
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchdogLastScan)

        watchdog.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchdogScanning)

        turbo.$isActive
            .receive(on: DispatchQueue.main)
            .assign(to: &$isTurboActive)

        turbo.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$turboProgress)

        sampler.start(interval: Pace.samplerClosed)
        network.start(interval: 2.5)
        Task { await turbo.syncFromSystem() }
        SharedMetricsSnapshot.write(from: displayMetrics, turbo: isTurboActive)

        thermalObserver.start { [weak self] level in
            guard let self else { return }
            var m = self.rawMetrics
            guard m.thermalLevel != level else { return }
            m.thermalLevel = level
            m.timestamp = Date()
            self.rawMetrics = m
            self.smoother.updateTarget(m)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isRunning else { return }
            self.watchdog.start(whitelist: self.whitelist, sampler: self.sampler)
            self.watchdog.setForeground(self.isPopoverOpen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runLaunchOptimizeIfNeeded()
        }

        // Periodic widget snapshot
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                SharedMetricsSnapshot.write(from: self.displayMetrics, turbo: self.isTurboActive)
            }
            .store(in: &cancellables)
    }

    func stop() {
        isRunning = false
        sampler.stop()
        smoother.stop()
        watchdog.stop()
        network.stop()
        thermalObserver.stop()
        // Never mdutil -a -i on at quit — that caused Spotlight reindex storms.
        turbo.detachWithoutRestoringSpotlight()
    }

    func popoverDidOpen() {
        isPopoverOpen = true
        sampler.setInterval(Pace.samplerOpen)
        smoother.start()
        sampler.kick()
        smoother.snap(to: rawMetrics)
        watchdog.setForeground(true)
        watchdog.kick()
        network.kick()
        turbo.refreshIndexingStatus()
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
        watchdog.setForeground(false)
    }

    private func runLaunchOptimizeIfNeeded() {
        guard LaunchAtLoginStore.shared.optimizeOnLaunch else { return }
        Task {
            _ = await PrivilegedRunner.run("/usr/bin/tmutil", args: ["stopbackup"], needsAdmin: false)
        }
    }

    private func publishReport(_ report: ActionReport) {
        reports.publish(report)
        lastReport = report
    }

    // MARK: - Smart RAM

    private func evaluateSmartRAM(_ metrics: SystemMetrics) {
        let critical = metrics.memoryPressure >= .critical
        let warn = metrics.memoryPressure >= .warning
        smartRAMSuggestionActive = warn

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
        content.categoryIdentifier = "FG_SMART_RAM"
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
            self.storageBuckets = await self.storageScanner.refreshAll()
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
            await self.watchdog.killAllHogs(whitelist: self.whitelist)
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
            publishReport(ActionReport(title: "Quit \(item.name)", processesQuit: 1))
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
            self.publishReport(ActionReport.fromCleanResult(result, title: "DNS flush"))
        }
    }

    func refreshStorageMap() {
        guard !storageScanning else { return }
        Task {
            storageScanning = true
            operationStatus = "Scanning storage…"
            operationDetail = "Measuring caches, Docker, Downloads…"
            defer {
                storageScanning = false
                if !isOptimizing {
                    operationStatus = nil
                    operationDetail = nil
                }
            }
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
            self.operationDetail = "Refreshing sizes…"
            self.publishReport(ActionReport.fromCleanResult(result, title: "Clean \(bucket.title)"))
            self.storageBuckets = await self.storageScanner.refreshAll()
        }
    }

    func coolDown() {
        runOperation(status: "Cooling down…", detail: "Quitting hogs · Low Power if on battery") {
            let thermalBefore = self.rawMetrics.thermalLevel
            let before = self.rawMetrics.memoryAvailableBytes
            let targets = self.watchdogItems.filter { $0.kind == .hog || $0.kind == .elevated }
            let count = targets.count
            await self.watchdog.killAllHogs(whitelist: self.whitelist)
            await PowerModeHelper.setLowPower(true, onlyOnBattery: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let thermalAfter = ThermalMonitor.sample()
            self.publishReport(ActionReport(
                title: "Cool down",
                availableBefore: before,
                availableAfter: MachMemory.sample()?.availableBytes ?? before,
                processesQuit: count,
                thermalBefore: thermalBefore,
                thermalAfter: thermalAfter,
                lowPowerChanged: true
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
