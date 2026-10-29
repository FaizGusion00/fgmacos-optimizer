import SwiftUI

enum CleanerTheme {
    static let accent = Color(red: 0.95, green: 0.45, blue: 0.12)
    static let accentDeep = Color(red: 0.88, green: 0.28, blue: 0.18)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let mist = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let panel = Color(red: 0.18, green: 0.19, blue: 0.22)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func riskColor(_ risk: CleanRisk) -> Color {
        switch risk {
        case .safeJunk: return TurboTheme.bandColor(.good)
        case .review: return TurboTheme.bandColor(.warn)
        case .destructive: return TurboTheme.bandColor(.bad)
        }
    }

    static func riskLabel(_ risk: CleanRisk) -> String {
        switch risk {
        case .safeJunk: return "Safe"
        case .review: return "Review"
        case .destructive: return "Careful"
        }
    }
}
