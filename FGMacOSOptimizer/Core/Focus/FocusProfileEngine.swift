import Foundation
import AppKit
import UserNotifications

enum FocusProfile: String, CaseIterable, Identifiable, Sendable {
    case off
    case meeting
    case coding
    case gaming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .meeting: return "Meeting"
        case .coding: return "Coding"
        case .gaming: return "Gaming"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "circle"
        case .meeting: return "video.fill"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .gaming: return "gamecontroller.fill"
        }
    }
}

/// Curated leftovers safe to quit during Meeting/Gaming (never whitelist / Apple).
/// Conferencing apps are a separate set: Meeting focus must never quit the meeting itself.
enum LeftoverApps {
    static let conferencingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark"
    ]

    static let conferencingNameHints: [String] = [
        "Zoom", "zoom.us", "Microsoft Teams", "Discord", "Webex", "FaceTime"
    ]

    static let helperBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap"
    ]

    static let helperNameHints: [String] = [
        "Google Chrome Helper",
        "Chrome Helper (Renderer)",
        "Slack Helper",
        "Discord Helper"
    ]

    static var bundleIDs: Set<String> { conferencingBundleIDs.union(helperBundleIDs) }
    static var nameHints: [String] { conferencingNameHints + helperNameHints }

    /// Anything in either set (explicit "Quit leftovers" action, Gaming focus).
    static func matches(bundleID: String?, name: String) -> Bool {
        matchesConferencing(bundleID: bundleID, name: name) || matchesHelpers(bundleID: bundleID, name: name)
    }

    static func matchesConferencing(bundleID: String?, name: String) -> Bool {
        if let bundleID, conferencingBundleIDs.contains(bundleID) { return true }
        return conferencingNameHints.contains { name.localizedCaseInsensitiveContains($0) }
    }

    /// Noisy helper processes only — safe during a meeting.
    static func matchesHelpers(bundleID: String?, name: String) -> Bool {
        if let bundleID, helperBundleIDs.contains(bundleID) { return true }
        for hint in helperNameHints where name.localizedCaseInsensitiveContains(hint) {
            return true
        }
        // Chrome helpers only — not the main Chrome browser window process name alone.
        if name.localizedCaseInsensitiveContains("Chrome Helper") { return true }
        return false
    }
}

@MainActor
final class FocusProfileEngine: ObservableObject {
    @Published private(set) var active: FocusProfile = .off
    @Published private(set) var statusMessage: String?

    private let defaultsKey = "fg.focus.activeProfile"
    private let turboByProfileKey = "fg.focus.enabledTurboForProfile"
    /// Persisted so "Focus off" after a relaunch still turns Soft Turbo back off.
    private var enabledTurboForProfile: Bool {
        get { UserDefaults.standard.bool(forKey: turboByProfileKey) }
        set { UserDefaults.standard.set(newValue, forKey: turboByProfileKey) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let profile = FocusProfile(rawValue: raw) {
            active = profile
        }
    }

    func apply(
        _ profile: FocusProfile,
        turbo: TurboModeEngine,
        watchdog: WatchdogEngine,
        whitelist: WhitelistStore
    ) async -> ActionReport {
        if profile == .off {
            return await deactivate(turbo: turbo)
        }

        statusMessage = "Applying \(profile.title)…"
        var quitCount = 0
        var lowPowerChanged = false
        let before = MachMemory.sample()?.availableBytes ?? 0
        var turboNote = "Turbo left alone"

        switch profile {
        case .meeting, .gaming:
            // Soft Turbo only (folder exclusions + stop TM) — never volume mdutil -a.
            // Never wipe Derived Data from a Focus profile: that is only the Turbo button's
            // explicitly confirmed path.
            if !turbo.isActive {
                let result = await turbo.activate(clearDerivedData: false)
                if result.error == nil {
                    enabledTurboForProfile = true
                    turboNote = "Soft Turbo on"
                }
            } else {
                // The user turned Turbo on themselves — Focus off must not take it away.
                turboNote = "Soft Turbo already on"
            }
            if profile == .meeting {
                openFocusSettingsHint()
                // Helpers only — never Zoom/Teams/FaceTime during a meeting.
                quitCount += await quitLeftovers(whitelist: whitelist, aggressive: false, helpersOnly: true)
                lowPowerChanged = await PowerModeHelper.setLowPower(true, onlyOnBattery: true)
            } else {
                quitCount += await quitLeftovers(whitelist: whitelist, aggressive: true, helpersOnly: false)
                lowPowerChanged = await PowerModeHelper.setLowPower(false, onlyOnBattery: false)
            }
        case .coding:
            // Do NOT activate Turbo — avoids Spotlight/DerivedData friction while coding in VS Code.
            let paused = await TimeMachineStatus.stopBackupIfRunning()
            turboNote = paused
                ? "Coding · no Turbo (Spotlight untouched) · backup paused"
                : "Coding · no Turbo (Spotlight untouched)"
        case .off:
            break
        }

        active = profile
        UserDefaults.standard.set(profile.rawValue, forKey: defaultsKey)
        statusMessage = "\(profile.title) focus on"
        let after = MachMemory.sample()?.availableBytes ?? before
        return ActionReport(
            title: "\(profile.title) focus",
            availableBefore: before,
            availableAfter: after,
            processesQuit: quitCount,
            focusName: profile.title,
            lowPowerChanged: lowPowerChanged,
            detail: turboNote
        )
    }

    func deactivate(turbo: TurboModeEngine) async -> ActionReport {
        statusMessage = "Restoring…"
        if enabledTurboForProfile, turbo.isActive {
            await turbo.deactivate()
        }
        enabledTurboForProfile = false
        active = .off
        UserDefaults.standard.set(FocusProfile.off.rawValue, forKey: defaultsKey)
        statusMessage = nil
        return ActionReport(title: "Focus off", focusName: "Off", detail: "Soft Turbo cleared if Focus had enabled it")
    }

    private func quitLeftovers(whitelist: WhitelistStore, aggressive: Bool, helpersOnly: Bool) async -> Int {
        var quit = 0
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            guard app.activationPolicy == .regular || aggressive else { continue }
            let name = app.localizedName ?? app.bundleURL?.lastPathComponent ?? "app"
            let bid = app.bundleIdentifier
            let matches = helpersOnly
                ? LeftoverApps.matchesHelpers(bundleID: bid, name: name)
                : LeftoverApps.matches(bundleID: bid, name: name)
            guard matches else { continue }
            guard whitelist.isKillCandidate(bundleID: bid, name: name, runningApp: app) else { continue }
            _ = app.terminate()
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !app.isTerminated { _ = app.forceTerminate() }
            quit += 1
        }
        return quit
    }

    private func openFocusSettingsHint() {
        // Deep-link to Focus / Notifications — user confirms DND; we don't silently rewrite Focus modes.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
