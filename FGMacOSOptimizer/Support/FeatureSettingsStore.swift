import Foundation
import Combine

@MainActor
final class FeatureSettingsStore: ObservableObject {
    static let shared = FeatureSettingsStore()

    private enum Keys {
        static let showMenuBarMeters = "fg.settings.showMenuBarMeters"
        static let autoFreeRAM = "fg.settings.autoFreeRAM"
        static let lastAutoFreeRAM = "fg.settings.lastAutoFreeRAM"
        static let historyPaused = "fg.settings.historyPaused"
        static let clearDerivedOnTurbo = "fg.settings.clearDerivedDataOnTurbo"
        static let keepInMenuBar = "fg.settings.keepInMenuBar.v1"
    }

    @Published var showMenuBarMeters: Bool {
        didSet { UserDefaults.standard.set(showMenuBarMeters, forKey: Keys.showMenuBarMeters) }
    }

    @Published var autoFreeRAMWhenCritical: Bool {
        didSet { UserDefaults.standard.set(autoFreeRAMWhenCritical, forKey: Keys.autoFreeRAM) }
    }

    @Published var historyCollectionPaused: Bool {
        didSet { UserDefaults.standard.set(historyCollectionPaused, forKey: Keys.historyPaused) }
    }

    /// Opt-in: Turbo may delete ~/Library/Developer/Xcode/DerivedData (default off — avoids Xcode/VS Code friction).
    @Published var clearDerivedDataOnTurbo: Bool {
        didSet { UserDefaults.standard.set(clearDerivedDataOnTurbo, forKey: Keys.clearDerivedOnTurbo) }
    }

    /// When false (default): quit when the menu popover closes and Cleaner isn’t open — no idle agent.
    @Published var keepInMenuBar: Bool {
        didSet { UserDefaults.standard.set(keepInMenuBar, forKey: Keys.keepInMenuBar) }
    }

    var lastAutoFreeRAMAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Keys.lastAutoFreeRAM)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastAutoFreeRAM)
        }
    }

    static let autoFreeCooldown: TimeInterval = 30 * 60

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Keys.showMenuBarMeters) == nil {
            showMenuBarMeters = true
        } else {
            showMenuBarMeters = d.bool(forKey: Keys.showMenuBarMeters)
        }
        autoFreeRAMWhenCritical = d.bool(forKey: Keys.autoFreeRAM)
        historyCollectionPaused = d.bool(forKey: Keys.historyPaused)
        clearDerivedDataOnTurbo = d.bool(forKey: Keys.clearDerivedOnTurbo)
        // Default OFF — open when you need it, don’t sit idle in the menu bar.
        if d.object(forKey: Keys.keepInMenuBar) == nil {
            keepInMenuBar = false
        } else {
            keepInMenuBar = d.bool(forKey: Keys.keepInMenuBar)
        }
    }

    func canAutoFreeRAMNow() -> Bool {
        guard autoFreeRAMWhenCritical else { return false }
        guard let last = lastAutoFreeRAMAt else { return true }
        return Date().timeIntervalSince(last) >= Self.autoFreeCooldown
    }

    func markAutoFreeRAM() {
        lastAutoFreeRAMAt = Date()
    }
}
