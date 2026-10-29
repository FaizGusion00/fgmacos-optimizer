import AppKit
import SwiftUI

/// Reliable permissions window for LSUIElement apps (Settings scene can be flaky).
@MainActor
enum PermissionsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible {
            PermissionManager.shared.refresh()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        PermissionManager.shared.refresh()
        let root = PermissionsGuideView()
            .environmentObject(PermissionManager.shared)
            .environmentObject(AppearanceStore.shared)
            .preferredColorScheme(AppearanceStore.shared.appearance.colorScheme)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome — FGMacOS Optimizer"
        window.minSize = NSSize(width: 480, height: 560)
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
    }
}
