import Foundation
import AppKit
import ApplicationServices
import UserNotifications
import Combine

@MainActor
final class WatchdogEngine: ObservableObject {
    @Published private(set) var items: [WatchdogItem] = []
    @Published private(set) var topProcesses: [TopProcess] = []
    @Published private(set) var lastScanAt: Date = .distantPast
    @Published private(set) var isScanning = false

    private var timer: Timer?
    private var hogStreak: [Int32: (count: Int, name: String, cpu: Double)] = [:]
    private var hungSince: [pid_t: Date] = [:]
    private var notifiedPIDs: Set<Int32> = []
    private weak var whitelist: WhitelistStore?

    private var scanInFlight = false
    private var tickCount = 0
    private var isForeground = false
    private var scanInterval: TimeInterval = 5.0
    private var lastHungScanAt: Date = .distantPast

    /// Alert / list threshold (visible in Watchdog)
    private let elevatedThreshold = 70.0
    /// Critical hog threshold (notifications)
    private let hogThreshold = 85.0
    private let hogStreakNeeded = 2
    private let hungGrace: TimeInterval = 45
    private let hungScanMinIntervalForeground: TimeInterval = 6
    private let hungScanMinIntervalBackground: TimeInterval = 20
    private let workQueue = DispatchQueue(label: "com.fgmacos.optimizer.watchdog", qos: .utility)

    static let killCategoryID = "FG_HOG_KILL"
    static let killActionID = "FG_KILL_NOW"

    func start(whitelist: WhitelistStore, sampler: MetricsSampler) {
        self.whitelist = whitelist
        registerNotificationCategory()
        setForeground(false)
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scanInFlight = false
    }

    func kick() { tick(forceHung: true, forceFull: true) }

    func setForeground(_ open: Bool) {
        isForeground = open
        scanInterval = open ? 2.5 : 6.0
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func registerNotificationCategory() {
        let kill = UNNotificationAction(
            identifier: Self.killActionID,
            title: "Kill Now",
            options: [.destructive, .authenticationRequired]
        )
        let category = UNNotificationCategory(
            identifier: Self.killCategoryID,
            actions: [kill],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func tick(forceHung: Bool = false, forceFull: Bool = false) {
        guard !scanInFlight else { return }
        scanInFlight = true
        tickCount &+= 1

        let showBusy = isForeground
        if showBusy { isScanning = true }

        let trusted = AXIsProcessTrusted()
        let hungDue = forceHung || Date().timeIntervalSince(lastHungScanAt) >= (
            isForeground ? hungScanMinIntervalForeground : hungScanMinIntervalBackground
        )
        let shouldHung = trusted && hungDue
        let mode: ProcessCPUSampler.Mode = (isForeground || forceFull) ? .full : .lite
        let limit = isForeground ? 18 : 10

        workQueue.async { [weak self] in
            let samples = ProcessCPUSampler.topConsumers(limit: limit, mode: mode)
            let hungPIDs = shouldHung ? Self.scanHungApps() : [:]
            DispatchQueue.main.async {
                guard let self else { return }
                if shouldHung { self.lastHungScanAt = Date() }
                self.process(samples: samples, hungFlags: hungPIDs, hungScanRan: shouldHung)
                self.isScanning = false
                self.lastScanAt = Date()
                self.scanInFlight = false
            }
        }
    }

    private static func scanHungApps() -> [pid_t: Bool] {
        var result: [pid_t: Bool] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            // Skip our own process.
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { continue }
            result[app.processIdentifier] = isHungViaAccessibility(pid: app.processIdentifier)
        }
        return result
    }

    private func process(samples: [ProcessCPUSampler.Sample], hungFlags: [pid_t: Bool], hungScanRan: Bool) {
        guard let whitelist else { return }

        let nextTop = samples.prefix(5).map {
            TopProcess(pid: $0.pid, name: $0.name, cpuPercent: $0.cpuPercent)
        }
        if !topProcessesApproximatelyEqual(topProcesses, Array(nextTop)) {
            topProcesses = Array(nextTop)
        }

        var nextItems: [WatchdogItem] = []
        var seenHot = Set<Int32>()

        for sample in samples {
            let app = NSRunningApplication(processIdentifier: sample.pid)
            let bundleID = app?.bundleIdentifier
            guard whitelist.isKillCandidate(bundleID: bundleID, name: sample.name, runningApp: app) else {
                continue
            }

            if sample.cpuPercent >= elevatedThreshold {
                seenHot.insert(sample.pid)
                let prev = hogStreak[sample.pid]?.count ?? 0
                hogStreak[sample.pid] = (prev + 1, sample.name, sample.cpuPercent)

                let isHog = sample.cpuPercent >= hogThreshold
                let streak = hogStreak[sample.pid]?.count ?? 0
                let kind: WatchdogItem.Kind = (isHog && streak >= hogStreakNeeded) ? .hog : .elevated

                let item = WatchdogItem(
                    id: "cpu-\(sample.pid)",
                    pid: sample.pid,
                    name: sample.name,
                    bundleID: bundleID,
                    kind: kind,
                    cpuPercent: sample.cpuPercent,
                    firstSeen: Date()
                )
                nextItems.append(item)

                if kind == .hog {
                    Task { await notifyHogIfNeeded(item) }
                }
            }
        }

        for pid in hogStreak.keys where !seenHot.contains(pid) {
            hogStreak.removeValue(forKey: pid)
            notifiedPIDs.remove(pid)
        }

        if hungScanRan {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                guard let name = app.localizedName else { continue }
                if whitelist.isProtected(bundleID: app.bundleIdentifier, name: name) { continue }
                let pid = app.processIdentifier
                if hungFlags[pid] == true {
                    let since = hungSince[pid] ?? Date()
                    hungSince[pid] = since
                    if Date().timeIntervalSince(since) >= hungGrace {
                        nextItems.append(
                            WatchdogItem(
                                id: "hung-\(pid)",
                                pid: pid,
                                name: name,
                                bundleID: app.bundleIdentifier,
                                kind: .hung,
                                cpuPercent: 0,
                                firstSeen: since
                            )
                        )
                    }
                } else {
                    hungSince.removeValue(forKey: pid)
                }
            }
        } else {
            // Keep existing hung items until next hung scan.
            nextItems.append(contentsOf: items.filter { $0.kind == .hung })
        }

        var byPID: [Int32: WatchdogItem] = [:]
        for item in nextItems {
            if let existing = byPID[item.pid] {
                let rank: (WatchdogItem.Kind) -> Int = { k in
                    switch k { case .hung: return 3; case .hog: return 2; case .elevated: return 1 }
                }
                if rank(item.kind) >= rank(existing.kind) { byPID[item.pid] = item }
            } else {
                byPID[item.pid] = item
            }
        }
        let sorted = Array(byPID.values).sorted { $0.cpuPercent > $1.cpuPercent }
        if !itemsVisuallyEqual(items, sorted) {
            items = sorted
        }
    }

    private func topProcessesApproximatelyEqual(_ a: [TopProcess], _ b: [TopProcess]) -> Bool {
        guard a.count == b.count else { return false }
        for (l, r) in zip(a, b) {
            if l.pid != r.pid || l.name != r.name { return false }
            if abs(l.cpuPercent - r.cpuPercent) > 2.0 { return false }
        }
        return true
    }

    private func itemsVisuallyEqual(_ a: [WatchdogItem], _ b: [WatchdogItem]) -> Bool {
        guard a.count == b.count else { return false }
        for (l, r) in zip(a, b) {
            if l.pid != r.pid || l.kind != r.kind || l.name != r.name { return false }
            if abs(l.cpuPercent - r.cpuPercent) > 2.5 { return false }
        }
        return true
    }

    func forceKill(item: WatchdogItem) async {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        guard item.pid > 1, item.pid != selfPID else { return }

        let app = NSRunningApplication(processIdentifier: item.pid)
        if let whitelist {
            guard whitelist.isKillCandidate(bundleID: item.bundleID ?? app?.bundleIdentifier, name: item.name, runningApp: app) else {
                let n = item.name
                AppLog.watchdog.error("Refused kill of protected process \(n, privacy: .public)")
                return
            }
        }

        let n = item.name
        AppLog.watchdog.info("Force quitting \(n, privacy: .public) pid=\(item.pid, privacy: .public)")

        guard let app else {
            AppLog.watchdog.error("No NSRunningApplication for pid=\(item.pid, privacy: .public)")
            return
        }
        if let bid = app.bundleIdentifier, bid.hasPrefix("com.apple.") || bid == Bundle.main.bundleIdentifier {
            return
        }
        _ = app.terminate()
        try? await Task.sleep(nanoseconds: 700_000_000)
        if !app.isTerminated { _ = app.forceTerminate() }

        items.removeAll { $0.pid == item.pid }
        hogStreak.removeValue(forKey: item.pid)
        hungSince.removeValue(forKey: item.pid)
        notifiedPIDs.remove(item.pid)
    }

    func killAllHogs(whitelist: WhitelistStore) async {
        let targets = items.filter { $0.kind == .hog || $0.kind == .elevated }
        for item in targets {
            await forceKill(item: item)
        }
    }

    func forceKillPID(_ pid: Int32) async {
        if let item = items.first(where: { $0.pid == pid }) {
            await forceKill(item: item)
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid),
              let name = app.localizedName else { return }
        let item = WatchdogItem(
            id: "notif-\(pid)",
            pid: pid,
            name: name,
            bundleID: app.bundleIdentifier,
            kind: .hog,
            cpuPercent: 0,
            firstSeen: Date()
        )
        await forceKill(item: item)
    }

    private static func isHungViaAccessibility(pid: pid_t) -> Bool {
        let appRef = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appRef, 0.15)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXRoleAttribute as CFString, &value)
        return result == .cannotComplete
    }

    private func notifyHogIfNeeded(_ item: WatchdogItem) async {
        guard !notifiedPIDs.contains(item.pid) else { return }
        notifiedPIDs.insert(item.pid)

        let ok = await PermissionManager.shared.requestNotificationsIfNeeded()
        guard ok else { return }

        let content = UNMutableNotificationContent()
        content.title = "CPU hog detected"
        content.body = "\(item.name) is using \(Int(item.cpuPercent))% CPU."
        content.sound = .default
        content.categoryIdentifier = Self.killCategoryID
        content.userInfo = ["pid": item.pid, "name": item.name]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "hog-\(item.pid)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
        AppLog.watchdog.info("Alerted hog \(item.name, privacy: .public)")
    }
}
