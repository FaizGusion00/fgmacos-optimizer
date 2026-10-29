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
enum LeftoverApps {
    static let bundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "com.apple.FaceTime"
    ]

    static let nameHints: [String] = [
        "Google Chrome Helper",
        "Chrome Helper (Renderer)",
        "Slack Helper",
        "Zoom",
        "zoom.us",
        "Microsoft Teams",
        "Discord Helper"
    ]

    static func matches(bundleID: String?, name: String) -> Bool {
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        for hint in nameHints where name.localizedCaseInsensitiveContains(hint) {
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
    private var enabledTurboForProfile = false

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
        let before = MachMemory.sample()?.availableBytes ?? 0
        var turboNote = "Turbo left alone"

        switch profile {
        case .meeting, .gaming:
            // Soft Turbo only (folder exclusions + stop TM) — never volume mdutil -a.
            if !turbo.isActive {
                let clearDD = FeatureSettingsStore.shared.clearDerivedDataOnTurbo
                let result = await turbo.activate(clearDerivedData: clearDD)
                if result.error == nil {
                    enabledTurboForProfile = true
                    turboNote = "Soft Turbo on"
                }
            } else {
                enabledTurboForProfile = true
                turboNote = "Soft Turbo already on"
            }
            if profile == .meeting {
                openFocusSettingsHint()
                quitCount += await quitLeftovers(whitelist: whitelist, aggressive: false)
                await PowerModeHelper.setLowPower(true, onlyOnBattery: true)
            } else {
                quitCount += await quitLeftovers(whitelist: whitelist, aggressive: true)
                await PowerModeHelper.setLowPower(false, onlyOnBattery: false)
            }
        case .coding:
            // Do NOT activate Turbo — avoids Spotlight/DerivedData friction while coding in VS Code.
            _ = await PrivilegedRunner.run(
                "/usr/bin/tmutil",
                args: ["stopbackup"],
                needsAdmin: false
            )
            turboNote = "Coding · no Turbo (Spotlight untouched)"
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
            lowPowerChanged: profile == .meeting || profile == .gaming,
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

    private func quitLeftovers(whitelist: WhitelistStore, aggressive: Bool) async -> Int {
        var quit = 0
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            guard app.activationPolicy == .regular || aggressive else { continue }
            let name = app.localizedName ?? app.bundleURL?.lastPathComponent ?? "app"
            let bid = app.bundleIdentifier
            guard LeftoverApps.matches(bundleID: bid, name: name) else { continue }
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
