import AppKit

/// SF Symbols for the menu-bar item. Prefer glyphs that exist on macOS 13 Ventura —
/// Sonoma-only names return nil and the status item becomes invisible.
enum StatusBarSymbol {
    static let idleCandidates = [
        "gauge.with.dots.needle.67percent", // Sonoma+
        "gauge.medium",
        "speedometer",
        "chart.bar.fill",
        "hare.fill"
    ]

    static let turboCandidates = [
        "bolt.fill",
        "bolt.circle.fill",
        "flame.fill"
    ]

    static func image(turboActive: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let names = turboActive ? turboCandidates : idleCandidates
        for name in names {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "FGMacOS Optimizer") else {
                continue
            }
            let image = base.withSymbolConfiguration(config) ?? base
            image.isTemplate = !turboActive
            return image
        }
        return textFallback()
    }

    private static func textFallback() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        NSString(string: "FG").draw(in: NSRect(x: 0, y: 2, width: 18, height: 14), withAttributes: attrs)
        image.isTemplate = true
        return image
    }
}
