import SwiftUI
import AppKit
import Combine

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Resolved NSAppearance for popover/window (fixes SwiftUI preferredColorScheme lag in NSPopover).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil // follow system
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

extension Notification.Name {
    static let fgAppearanceDidChange = Notification.Name("fg.appearanceDidChange")
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
            applyNow()
        }
    }

    private enum Keys {
        static let appearance = "fg.appearance.mode"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.appearance),
           let value = AppAppearance(rawValue: raw) {
            appearance = value
        } else {
            appearance = .system
        }
        // Ensure first apply after init (didSet won't fire for init assignment in all paths)
        DispatchQueue.main.async { [weak self] in self?.applyNow() }
    }

    /// One-tap Light↔Dark (always visibly changes). Hold Auto via set(.system).
    func toggleLightDark() {
        let currentlyDark: Bool = {
            if let scheme = appearance.colorScheme {
                return scheme == .dark
            }
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()
        appearance = currentlyDark ? .light : .dark
    }

    func set(_ value: AppAppearance) {
        appearance = value
    }

    func applyNow() {
        NotificationCenter.default.post(name: .fgAppearanceDidChange, object: appearance)
    }

    func apply(to view: NSView?) {
        guard let view else { return }
        view.appearance = appearance.nsAppearance
        view.window?.appearance = appearance.nsAppearance
        view.needsDisplay = true
        view.subviews.forEach { $0.needsDisplay = true }
    }
}
