import AppKit
import SwiftUI

@MainActor
enum CleanerWindowController {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static var isVisible: Bool {
        window?.isVisible == true
    }

    /// True while the window exists, even miniaturized — on-demand quit must wait for it.
    static var exists: Bool {
        window != nil
    }

    #if DEBUG
    static var debugWindow: NSWindow? { window }
    #endif

    static func show(showIntroIfNeeded: Bool = false) {
        if let window {
            // Visible or miniaturized: bring the existing window back, never a second one.
            if window.isMiniaturized { window.deminiaturize(nil) }
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
                NotificationCenter.default.post(name: .fgRequestOnDemandQuit, object: "cleaner")
            }
        }

        Task {
            await CleanerStore.shared.refresh()
        }
    }
}
