import Foundation
import AppKit
import ApplicationServices
import UserNotifications
import Combine

/// Centralizes when and how we request macOS permissions — never spam at launch.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted = false
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    private enum Keys {
        static let onboarding = "fg.permissions.onboardingDone"
        static let notifiedAsk = "fg.permissions.notificationsAsked"
    }

    private init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.onboarding)
        refresh()
    }

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    /// Call only from Permissions UI or first intentional Watchdog alert path.
    func requestNotificationsIfNeeded() async -> Bool {
        refresh()
        if notificationStatus == .authorized || notificationStatus == .provisional {
            return true
        }
        if notificationStatus == .denied {
            openNotificationsPane()
            return false
        }
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        UserDefaults.standard.set(true, forKey: Keys.notifiedAsk)
        refresh()
        return granted
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openPrivacyPane("Privacy_Accessibility")
        // Status updates after user returns from Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    func openFullDiskAccess() {
        // macOS Ventura+ and legacy URLs
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func openAutomationPane() {
        openPrivacyPane("Privacy_Automation")
    }

    func openNotificationsPane() {
        openPrivacyPane("Privacy_Notifications")
    }

    private func openPrivacyPane(_ anchor: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Probe whether Library/Caches is readable (FDA heuristic).
    func hasCacheAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Caches"
        return FileManager.default.isReadableFile(atPath: path)
            && (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}
