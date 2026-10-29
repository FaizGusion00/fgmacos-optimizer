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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cleaner — FGMacOS Optimizer"
        window.titlebarAppearsTransparent = false
        window.contentViewController = hosting
        window.minSize = NSSize(width: 780, height: 540)
        window.backgroundColor = NSColor.windowBackgroundColor
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
