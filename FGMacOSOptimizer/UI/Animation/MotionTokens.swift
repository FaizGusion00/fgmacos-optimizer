import SwiftUI

enum MotionTokens {
    /// Snappy spring for gauge needles / arc fills.
    static let gauge = Animation.spring(response: 0.35, dampingFraction: 0.72)

    /// Soft spring for panel / zone appear.
    static let panel = Animation.spring(response: 0.45, dampingFraction: 0.86)

    /// Emphatic spring for Turbo Mode CTA.
    static let turbo = Animation.spring(response: 0.28, dampingFraction: 0.55)

    static let appearFast = Animation.easeOut(duration: 0.22)
    static let glowPulse = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)

    static let zoneStagger: [Double] = [0.0, 0.04, 0.08]

    static let turboSweepDuration: TimeInterval = 0.8
}
