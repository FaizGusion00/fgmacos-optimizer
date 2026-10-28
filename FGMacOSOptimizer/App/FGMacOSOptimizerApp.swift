import SwiftUI

@main
struct FGMacOSOptimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar only. Permissions use PermissionsWindowController for reliability.
        Settings {
            PermissionsGuideView()
                .environmentObject(PermissionManager.shared)
                .environmentObject(AppearanceStore.shared)
                .preferredColorScheme(AppearanceStore.shared.appearance.colorScheme)
                .frame(width: 440, height: 520)
        }
    }
}
