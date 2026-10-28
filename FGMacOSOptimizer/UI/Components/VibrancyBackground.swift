import SwiftUI
import AppKit

struct VibrancyBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var appearance: AppAppearance = .system

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.masksToBounds = true
        applyAppearance(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        applyAppearance(nsView)
    }

    private func applyAppearance(_ view: NSVisualEffectView) {
        view.appearance = appearance.nsAppearance
        view.window?.appearance = appearance.nsAppearance
    }
}
