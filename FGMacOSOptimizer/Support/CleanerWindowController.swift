import AppKit
import SwiftUI

@MainActor
enum CleanerWindowController {
    private static var window: NSWindow?

    static func show(showIntroIfNeeded: Bool = false) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Task { await CleanerStore.shared.refresh() }
            return
        }

        CleanerStore.shared.tab = .smartCare
        if showIntroIfNeeded {
            CleanerStore.shared.showGuideBanner = PermissionManager.shared.shouldShowCleanerIntro
        }

        let root = CleanerRootView()
            .environmentObject(CleanerStore.shared)
            .environmentObject(AppearanceStore.shared)
            .preferredColorScheme(AppearanceStore.shared.appearance.colorScheme)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cleaner — FGMacOS Optimizer"
        window.contentViewController = hosting
        window.minSize = NSSize(width: 800, height: 560)
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
