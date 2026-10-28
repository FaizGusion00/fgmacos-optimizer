import AppKit
import SwiftUI

/// Reliable permissions window for LSUIElement apps (Settings scene can be flaky).
@MainActor
enum PermissionsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible {
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Permissions — FGMacOS Optimizer"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}
