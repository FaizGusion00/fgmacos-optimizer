import SwiftUI

enum Design {
    static let popoverWidth: CGFloat = 340
    static let popoverHeight: CGFloat = 760
    static let radius: CGFloat = 14
    static let radiusSm: CGFloat = 10

    /// High-contrast text for frosted popovers (Light + Dark).
    enum Text {
        static let title = Font.system(size: 16, weight: .bold, design: .rounded)
        static let section = Font.system(size: 12, weight: .bold, design: .rounded)
        static let body = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let caption = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let micro = Font.system(size: 10, weight: .semibold, design: .rounded)
    }
}

struct TurboTheme {
    let isActive: Bool

    var accent: Color {
        isActive ? Color(red: 0.95, green: 0.30, blue: 0.34) : Color(red: 0.10, green: 0.45, blue: 0.98)
    }

    var accentSecondary: Color {
        isActive ? Color(red: 1.0, green: 0.52, blue: 0.20) : Color(red: 0.28, green: 0.68, blue: 1.0)
    }

    var turboGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func bandColor(_ band: MetricBand) -> Color {
        switch band {
        case .good: return Color(red: 0.08, green: 0.68, blue: 0.42)
        case .warn: return Color(red: 0.92, green: 0.58, blue: 0.05)
        case .bad: return Color(red: 0.90, green: 0.22, blue: 0.25)
        }
    }

    /// Primary label — stronger than default `.primary` on vibrancy.
    static func primaryLabel(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(white: 0.08) : Color(white: 0.96)
    }

    static func secondaryLabel(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(white: 0.28) : Color(white: 0.78)
    }

    static func tertiaryLabel(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(white: 0.42) : Color(white: 0.62)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.11)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.14)
    }
}
