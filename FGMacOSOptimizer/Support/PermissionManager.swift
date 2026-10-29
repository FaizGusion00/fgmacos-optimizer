import Foundation
import AppKit
import ApplicationServices
import UserNotifications
import Combine

/// Requests and tracks macOS permissions. First-run wizard asks up front — all optional to continue.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted = false
    /// User opened Accessibility settings while this process was still untrusted.
    /// macOS only applies the toggle to *new* processes — relaunch required.
    @Published var accessibilityAwaitingRelaunch = false
    /// Relaunched but AX still false — Settings toggle was stale (common with ad-hoc rebuilds).
    @Published var accessibilityNeedsRetoggle = false
    @Published var fullDiskLooksOK = false
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    private enum Keys {
        static let onboarding = "fg.permissions.onboardingDone.v2"
        static let notifiedAsk = "fg.permissions.notificationsAsked"
        static let cleanerIntro = "fg.cleaner.introShown.v1"
        static let reopenCleaner = "fg.permissions.reopenCleanerAfterRelaunch"
        static let axAwaiting = "fg.permissions.accessibilityAwaitingRelaunch"
    }

    enum AccessibilityDisplay {
        case on
        case restartToApply
        case retoggle
        case off
    }

    var accessibilityDisplay: AccessibilityDisplay {
        if accessibilityTrusted { return .on }
        if accessibilityNeedsRetoggle { return .retoggle }
        if accessibilityAwaitingRelaunch { return .restartToApply }
        return .off
    }

    /// Call after a forced relaunch when AX is still false.
    func markAccessibilityRelaunchDidNotApply() {
        accessibilityNeedsRetoggle = true
        accessibilityAwaitingRelaunch = false
        UserDefaults.standard.set(false, forKey: Keys.axAwaiting)
        AppLog.lifeFile("AX still false after relaunch — need OFF→ON retoggle \(permissionSnapshot())")
    }

    var shouldShowCleanerIntro: Bool {
        !UserDefaults.standard.bool(forKey: Keys.cleanerIntro)
    }

    func markCleanerIntroShown() {
        UserDefaults.standard.set(true, forKey: Keys.cleanerIntro)
    }

    func markReopenCleanerAfterRelaunch() {
        UserDefaults.standard.set(true, forKey: Keys.reopenCleaner)
        UserDefaults.standard.set(false, forKey: Keys.axAwaiting)
        accessibilityAwaitingRelaunch = false
        hasCompletedOnboarding = true
    }

    var shouldReopenCleanerAfterRelaunch: Bool {
        UserDefaults.standard.bool(forKey: Keys.reopenCleaner)
    }

    func clearReopenCleanerFlag() {
        UserDefaults.standard.set(false, forKey: Keys.reopenCleaner)
    }

    private init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.onboarding)
        accessibilityAwaitingRelaunch = UserDefaults.standard.bool(forKey: Keys.axAwaiting)
        refresh()
        AppLog.lifeFile(permissionSnapshot())
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        accessibilityTrusted = ax
        if ax {
            accessibilityAwaitingRelaunch = false
            accessibilityNeedsRetoggle = false
            UserDefaults.standard.set(false, forKey: Keys.axAwaiting)
        }
        fullDiskLooksOK = probeFullDiskAccess()
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func permissionSnapshot() -> String {
        "permissions AX=\(accessibilityTrusted) axPendingRestart=\(accessibilityAwaitingRelaunch) notif=\(notificationStatus.rawValue) fda=\(fullDiskLooksOK)"
    }

    var notificationsOK: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }

    func requestAllRecommended() async {
        _ = await requestNotificationsIfNeeded()
        if !accessibilityTrusted {
            requestAccessibility(openSettings: true)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        if !fullDiskLooksOK {
            openFullDiskAccess()
        }
        refresh()
        AppLog.lifeFile("requestAllRecommended → \(permissionSnapshot())")
    }

    func requestNotificationsIfNeeded() async -> Bool {
        let settings = await notificationSettings()
        notificationStatus = settings.authorizationStatus
        if notificationsOK { return true }
        if settings.authorizationStatus == .denied {
            openNotificationsPane()
            return false
        }
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        UserDefaults.standard.set(true, forKey: Keys.notifiedAsk)
        refresh()
        return granted
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { cont in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                cont.resume(returning: settings)
            }
        }
    }

    func requestAccessibility(openSettings: Bool = true) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trustedNow = AXIsProcessTrustedWithOptions(opts)
        accessibilityTrusted = trustedNow
        if !trustedNow {
            accessibilityAwaitingRelaunch = true
            UserDefaults.standard.set(true, forKey: Keys.axAwaiting)
        }
        if openSettings {
            openPrivacyPane("Privacy_Accessibility")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
            if let self {
                AppLog.lifeFile("accessibility after open settings → \(self.permissionSnapshot())")
            }
        }
    }

    /// Quit + reopen so macOS applies Accessibility to this binary.
    func quitAndRelaunch(openCleaner: Bool = true) {
        if openCleaner {
            markReopenCleanerAfterRelaunch()
        } else {
            hasCompletedOnboarding = true
            UserDefaults.standard.set(false, forKey: Keys.axAwaiting)
            accessibilityAwaitingRelaunch = false
        }
        AppLog.lifeFile("quitAndRelaunch openCleaner=\(openCleaner) pre=\(permissionSnapshot())")
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", appURL.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    func openFullDiskAccess() {
        openFirstURL([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ])
    }

    func openAutomationPane() {
        openPrivacyPane("Privacy_Automation")
    }

    func openNotificationsPane() {
        openFirstURL([
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Notifications"
        ])
    }

    private func openPrivacyPane(_ anchor: String) {
        openFirstURL([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ])
    }

    private func openFirstURL(_ candidates: [String]) {
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func hasCacheAccess() -> Bool { probeFullDiskAccess() }

    private func probeFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let protected = [
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Messages",
            NSHomeDirectory() + "/Library/Safari"
        ]
        for path in protected {
            if fm.isReadableFile(atPath: path),
               (try? fm.contentsOfDirectory(atPath: path)) != nil {
                return true
            }
        }
        return false
    }
}
