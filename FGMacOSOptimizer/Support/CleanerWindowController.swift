import AppKit
import SwiftUI

@MainActor
enum CleanerWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = CleanerRootView()
            .environmentObject(CleanerStore.shared)
            .environmentObject(AppearanceStore.shared)
            .preferredColorScheme(AppearanceStore.shared.appearance.colorScheme)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cleaner — FGMacOS Optimizer"
        window.contentViewController = hosting
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window

        Task {
            await CleanerStore.shared.refresh()
        }
    }
}
