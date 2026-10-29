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
        static let samplerOpen: TimeInterval = 1.0
        static let samplerClosed: TimeInterval = 4.0
        static let samplerAfterAction: TimeInterval = 1.2
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
        turbo.syncFromSystem()
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
        if isTurboActive {
            Task { await turbo.deactivate() }
        }
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
            Task {
                isOptimizing = true
                defer { isOptimizing = false }
                let before = rawMetrics.memoryAvailableBytes
                await turbo.deactivate()
                publishReport(ActionReport(
                    title: "Turbo off",
                    availableBefore: before,
                    availableAfter: MachMemory.sample()?.availableBytes ?? before,
                    detail: "Spotlight indexing resumed"
                ))
            }
            return
        }

        let confirmed = confirm(
            title: "Enable Turbo Mode?",
            message: "Pauses Spotlight INDEXING (background reindex that burns CPU/disk). Spotlight SEARCH still works — that is normal.\n\nAlso stops Time Machine backups in progress and clears Xcode Derived Data.\n\nTurbo does NOT free RAM. Use Free RAM for that."
        )
        guard confirmed else { return }

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let before = rawMetrics.memoryAvailableBytes
            let result = await turbo.activate()
            if let error = result.error {
                actionError = error
                if error.localizedCaseInsensitiveContains("cancel") {
                    lastAuthCancelAt = Date()
                }
            } else {
                publishReport(ActionReport(
                    title: "Turbo on",
                    availableBefore: before,
                    availableAfter: MachMemory.sample()?.availableBytes ?? before,
                    detail: "Indexing paused"
                ))
            }
            sampler.kick()
        }
    }

    func clearCache() {
        let confirmed = confirm(
            title: "Deep Clean?",
            message: "Safely clears allow-listed caches under ~/Library/Caches. DNS flush needs your admin password. Docker dangling volumes are pruned only if Docker is installed."
        )
        guard confirmed else { return }

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let before = rawMetrics.memoryAvailableBytes
            let result = await cleaner.runDeepClean()
            lastCleanResult = result
            let after = MachMemory.sample()?.availableBytes ?? before
            publishReport(ActionReport(
                title: "Deep Clean",
                availableBefore: before,
                availableAfter: after,
                bytesCleaned: result.cacheBytesFreed,
                dnsFlushed: result.dnsFlushed,
                detail: result.summary
            ))
            if isPopoverOpen {
                sampler.setInterval(Pace.samplerAfterAction)
                sampler.kick()
            }
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

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let result = await cleaner.purgeInactiveMemory()
            lastCleanResult = result
            if !result.memoryPurged {
                actionError = "Purge cancelled or failed. Admin permission is required."
                lastAuthCancelAt = Date()
            } else {
                publishReport(ActionReport.fromCleanResult(
                    result,
                    title: fromSmartSuggest ? "Smart Free RAM" : "Free RAM"
                ))
            }
            sampler.kick()
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

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let before = rawMetrics.memoryAvailableBytes
            let count = hogs.count
            await watchdog.killAllHogs(whitelist: whitelist)
            publishReport(ActionReport(
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
        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let report = await focus.apply(profile, turbo: turbo, watchdog: watchdog, whitelist: whitelist)
            publishReport(report)
            sampler.kick()
        }
    }

    func flushDNS() {
        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let result = await cleaner.flushDNSOnly()
            lastCleanResult = result
            publishReport(ActionReport.fromCleanResult(result, title: "DNS flush"))
        }
    }

    func refreshStorageMap() {
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
                message: "This permanently deletes files in \(bucket.title). Continue?"
            )
            guard confirmed else { return }
        }
        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let result = await cleaner.cleanBucket(bucket)
            lastCleanResult = result
            publishReport(ActionReport.fromCleanResult(result, title: "Clean \(bucket.title)"))
            storageBuckets = await storageScanner.refreshAll()
        }
    }

    func coolDown() {
        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let thermalBefore = rawMetrics.thermalLevel
            let before = rawMetrics.memoryAvailableBytes
            let targets = watchdogItems.filter { $0.kind == .hog || $0.kind == .elevated }
            let count = targets.count
            await watchdog.killAllHogs(whitelist: whitelist)
            await PowerModeHelper.setLowPower(true, onlyOnBattery: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let thermalAfter = ThermalMonitor.sample()
            publishReport(ActionReport(
                title: "Cool down",
                availableBefore: before,
                availableAfter: MachMemory.sample()?.availableBytes ?? before,
                processesQuit: count,
                thermalBefore: thermalBefore,
                thermalAfter: thermalAfter,
                lowPowerChanged: true
            ))
            sampler.kick()
        }
    }

    func quitLeftovers() {
        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            var quit = 0
            for app in NSWorkspace.shared.runningApplications {
                let name = app.localizedName ?? ""
                let bid = app.bundleIdentifier
                guard LeftoverApps.matches(bundleID: bid, name: name) else { continue }
                guard whitelist.isKillCandidate(bundleID: bid, name: name, runningApp: app) else { continue }
                _ = app.terminate()
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !app.isTerminated { _ = app.forceTerminate() }
                quit += 1
            }
            publishReport(ActionReport(title: "Quit leftovers", processesQuit: quit))
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
