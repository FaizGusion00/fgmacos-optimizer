import Foundation
import UserNotifications
import Combine
import AppKit

enum SmartCareScheduleFrequency: String, CaseIterable, Identifiable, Sendable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }
}

/// Auto-scans Smart Care on a schedule and notifies — never cleans without user confirm.
@MainActor
final class SmartCareScheduler: ObservableObject {
    static let shared = SmartCareScheduler()

    static let notificationID = "fg.smartcare.scheduled"
    static let reviewActionID = "fg.smartcare.review"
    static let categoryID = "fg.smartcare.category"

    private enum Keys {
        static let frequency = "fg.smartcare.schedule.frequency"
        static let lastScan = "fg.smartcare.schedule.lastScan"
        static let lastBytes = "fg.smartcare.schedule.lastBytes"
        static let lastItemCount = "fg.smartcare.schedule.lastItemCount"
    }

    @Published var frequency: SmartCareScheduleFrequency {
        didSet { UserDefaults.standard.set(frequency.rawValue, forKey: Keys.frequency) }
    }

    @Published private(set) var lastScanAt: Date?
    @Published private(set) var lastFoundBytes: UInt64 = 0
    @Published private(set) var lastItemCount: Int = 0
    @Published private(set) var isScanning = false
    @Published var status: String?

    private var timer: Timer?
    private let engine = SmartCareEngine()

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.frequency) ?? SmartCareScheduleFrequency.off.rawValue
        frequency = SmartCareScheduleFrequency(rawValue: raw) ?? .off
        let t = UserDefaults.standard.double(forKey: Keys.lastScan)
        lastScanAt = t > 0 ? Date(timeIntervalSince1970: t) : nil
        lastFoundBytes = UInt64(UserDefaults.standard.double(forKey: Keys.lastBytes))
        lastItemCount = UserDefaults.standard.integer(forKey: Keys.lastItemCount)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runIfDue(reason: "timer")
            }
        }
        timer?.tolerance = 120
        Task { await runIfDue(reason: "launch") }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var nextDueDescription: String {
        guard let interval = frequency.interval else { return "Scheduling is off" }
        guard let last = lastScanAt else { return "Next scan: soon (after enable)" }
        let next = last.addingTimeInterval(interval)
        if next <= Date() { return "Next scan: due now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Next scan: \(formatter.localizedString(for: next, relativeTo: Date()))"
    }

    func runNow() async {
        await performScan(notify: true, reason: "manual")
    }

    func runIfDue(reason: String) async {
        guard let interval = frequency.interval else { return }
        if let last = lastScanAt, Date().timeIntervalSince(last) < interval {
            return
        }
        await performScan(notify: true, reason: reason)
    }

    private func performScan(notify: Bool, reason: String) async {
        guard !isScanning else { return }
        isScanning = true
        status = "Scheduled Smart Care scanning…"
        defer {
            isScanning = false
            if status == "Scheduled Smart Care scanning…" { status = nil }
        }

        let raw = await engine.scan(includeDev: true)
        let items = ProtectionGuard.filterItems(raw).filter { $0.id != "smart.ram" && $0.bytes > 0 }
        let bytes = items.filter(\.selected).reduce(UInt64(0)) { $0 + $1.bytes }
        let count = items.filter(\.selected).count

        lastScanAt = Date()
        lastFoundBytes = bytes
        lastItemCount = count
        UserDefaults.standard.set(lastScanAt!.timeIntervalSince1970, forKey: Keys.lastScan)
        UserDefaults.standard.set(Double(bytes), forKey: Keys.lastBytes)
        UserDefaults.standard.set(count, forKey: Keys.lastItemCount)

        AppLog.lifeFile("smartCare schedule scan reason=\(reason) bytes=\(bytes) items=\(count)")
        status = bytes > 0
            ? "Found \(CleanSafety.formatBytes(bytes)) safe to review"
            : "No significant junk found"

        guard notify, bytes > 0 else { return }
        await postReviewNotification(bytes: bytes, count: count)
    }

    private func postReviewNotification(bytes: UInt64, count: Int) async {
        _ = await PermissionManager.shared.requestNotificationsIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Smart Care found space to free"
        content.body = "About \(CleanSafety.formatBytes(bytes)) across \(count) items. Nothing was deleted — tap to review."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["fg.action": "openSmartCare"]
        let req = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(req)
    }

    func openCleanerForReview() {
        CleanerWindowController.show(showIntroIfNeeded: false)
        CleanerStore.shared.tab = .smartCare
        Task { await CleanerStore.shared.refresh() }
    }
}
