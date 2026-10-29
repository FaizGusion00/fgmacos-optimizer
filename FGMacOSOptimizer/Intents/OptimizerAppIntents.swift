import AppIntents
import AppKit

@available(macOS 13.0, *)
struct FreeRAMIntent: AppIntent {
    static var title: LocalizedStringResource = "Free RAM"
    static var description = IntentDescription("Purge reclaimable disk cache to free RAM.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(dialog: "FGMacOS Optimizer is not running.")
        }
        delegate.appState.freeRAM(skipConfirm: true, fromSmartSuggest: false)
        return .result(dialog: "Free RAM started.")
    }
}

@available(macOS 13.0, *)
struct ToggleTurboIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Turbo Mode"
    static var description = IntentDescription("Pause or resume Spotlight indexing (Turbo).")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(dialog: "FGMacOS Optimizer is not running.")
        }
        delegate.appState.toggleTurbo()
        return .result(dialog: "Turbo toggled.")
    }
}

@available(macOS 13.0, *)
struct ApplyFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Focus Profile"
    static var description = IntentDescription("Apply Meeting, Coding, Gaming, or Off.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Profile")
    var profile: FocusProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(dialog: "FGMacOS Optimizer is not running.")
        }
        let mapped: FocusProfile
        switch profile {
        case .meeting: mapped = .meeting
        case .coding: mapped = .coding
        case .gaming: mapped = .gaming
        case .off: mapped = .off
        }
        delegate.appState.applyFocus(mapped)
        return .result(dialog: "Applied \(mapped.title).")
    }
}

@available(macOS 13.0, *)
struct FlushDNSIntent: AppIntent {
    static var title: LocalizedStringResource = "Flush DNS"
    static var description = IntentDescription("Flush DNS cache.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return .result(dialog: "FGMacOS Optimizer is not running.")
        }
        delegate.appState.flushDNS()
        return .result(dialog: "DNS flush started.")
    }
}

@available(macOS 13.0, *)
enum FocusProfileEntity: String, AppEnum {
    case meeting, coding, gaming, off

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Focus Profile")
    static var caseDisplayRepresentations: [FocusProfileEntity: DisplayRepresentation] = [
        .meeting: "Meeting",
        .coding: "Coding",
        .gaming: "Gaming",
        .off: "Off"
    ]
}

@available(macOS 13.0, *)
struct OptimizerAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FreeRAMIntent(),
            phrases: [
                "Free RAM with \(.applicationName)",
                "Purge memory with \(.applicationName)"
            ],
            shortTitle: "Free RAM",
            systemImageName: "memorychip"
        )
        AppShortcut(
            intent: ToggleTurboIntent(),
            phrases: ["Toggle Turbo with \(.applicationName)"],
            shortTitle: "Turbo",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: FlushDNSIntent(),
            phrases: ["Flush DNS with \(.applicationName)"],
            shortTitle: "Flush DNS",
            systemImageName: "network"
        )
    }
}
