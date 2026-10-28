import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    /// Latest raw sample (not published — avoids double UI refresh with displayMetrics).
    private(set) var rawMetrics = SystemMetrics.zero
    @Published var displayMetrics = SystemMetrics.zero
    @Published var isTurboActive = false
    @Published var isOptimizing = false
    @Published var lastCleanResult: CleanResult?
    @Published var watchdogItems: [WatchdogItem] = []
    @Published var topProcesses: [TopProcess] = []
    @Published var watchdogLastScan: Date = .distantPast
    @Published var watchdogScanning = false
    @Published var turboProgress: String?
    @Published var actionError: String?

    let sampler = MetricsSampler()
    let smoother = MetricSmoother()
    let watchdog = WatchdogEngine()
    let turbo = TurboModeEngine()
    let cleaner = SystemCleaner()
    let whitelist = WhitelistStore()

    private var cancellables = Set<AnyCancellable>()
    private var isPopoverOpen = false
    private var isRunning = false
    private let thermalObserver = ThermalStateObserver()

    /// Idle vs live intervals — keep background cheap, popover snappy.
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
                // Skip no-op publishes that still force SwiftUI body eval.
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
            }
            .store(in: &cancellables)

        watchdog.$items
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchdogItems)

        watchdog.$topProcesses
            .receive(on: DispatchQueue.main)
            .assign(to: &$topProcesses)

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

        // Start calm — popover open bumps pace.
        sampler.start(interval: Pace.samplerClosed)
        turbo.syncFromSystem()

        thermalObserver.start { [weak self] level in
            guard let self else { return }
            var m = self.rawMetrics
            guard m.thermalLevel != level else { return }
            m.thermalLevel = level
            m.timestamp = Date()
            self.rawMetrics = m
            self.smoother.updateTarget(m)
        }

        // Delay Watchdog so launch stays light.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isRunning else { return }
            self.watchdog.start(whitelist: self.whitelist, sampler: self.sampler)
            self.watchdog.setForeground(self.isPopoverOpen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runLaunchOptimizeIfNeeded()
        }

        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MemoryBudget.logIfOverBudget(tag: "startup+4s")
        }
        #endif
    }

    func stop() {
        isRunning = false
        sampler.stop()
        smoother.stop()
        watchdog.stop()
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
        turbo.refreshIndexingStatus()
        // Keep Turbo UI honest if user toggled indexing outside the app.
        if turbo.indexingDisabledVerified != isTurboActive {
            // Prefer system truth for Spotlight indexing.
            if turbo.indexingDisabledVerified {
                isTurboActive = true
            }
        }
    }

    func popoverDidClose() {
        isPopoverOpen = false
        sampler.setInterval(Pace.samplerClosed)
        // Freeze gauge animation — last frame stays valid for next open.
        smoother.stop()
        watchdog.setForeground(false)
    }

    private func runLaunchOptimizeIfNeeded() {
        guard LaunchAtLoginStore.shared.optimizeOnLaunch else { return }
        Task {
            _ = await PrivilegedRunner.run("/usr/bin/tmutil", args: ["stopbackup"], needsAdmin: false)
        }
        if isTurboActive {
            AppLog.turbo.info("Launch optimize: Turbo already active (Spotlight off)")
        }
    }

    // MARK: - Actions

    func toggleTurbo() {
        if isTurboActive {
            Task {
                isOptimizing = true
                defer { isOptimizing = false }
                await turbo.deactivate()
            }
            return
        }

        let confirmed = confirm(
            title: "Enable Turbo Mode?",
            message: "Pauses Spotlight INDEXING (background reindex that burns CPU/disk). Spotlight SEARCH still works — that is normal.\n\nAlso stops Time Machine backups in progress and clears Xcode Derived Data.\n\nTurbo does NOT free RAM. Use Free RAM for that. Swap pressure is separate from Turbo."
        )
        guard confirmed else { return }

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let result = await turbo.activate()
            if let error = result.error {
                actionError = error
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
            lastCleanResult = await cleaner.runDeepClean()
            if isPopoverOpen {
                sampler.setInterval(Pace.samplerAfterAction)
                sampler.kick()
            }
        }
    }

    func freeRAM() {
        let confirmed = confirm(
            title: "Free RAM (purge disk cache)?",
            message: "Runs macOS `purge` (admin password) to drop reclaimable file cache.\n\nApps stay open. Available memory should rise briefly — macOS may refill cache as you work. That is healthy, not a leak."
        )
        guard confirmed else { return }

        Task {
            isOptimizing = true
            defer { isOptimizing = false }
            let result = await cleaner.purgeInactiveMemory()
            lastCleanResult = result
            if !result.memoryPurged {
                actionError = "Purge cancelled or failed. Admin permission is required."
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
            await watchdog.killAllHogs(whitelist: whitelist)
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
