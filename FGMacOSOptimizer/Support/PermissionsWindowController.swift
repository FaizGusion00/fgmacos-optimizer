import AppKit
import SwiftUI

/// Reliable permissions window for LSUIElement apps (Settings scene can be flaky).
@MainActor
enum PermissionsWindowController {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static var isVisible: Bool {
        window?.isVisible == true
    }

    /// True while the window exists — on-demand quit must wait for it.
    static var exists: Bool {
        window != nil
    }

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

        // Red-X close must also let the on-demand app quit (orderOut path below too).
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                Self.closeObserver = nil
                Self.window = nil
                NotificationCenter.default.post(name: .fgRequestOnDemandQuit, object: "permissions")
            }
        }
    }

    static func close() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window?.orderOut(nil)
        window = nil
        NotificationCenter.default.post(name: .fgRequestOnDemandQuit, object: "permissions")
    }
}
