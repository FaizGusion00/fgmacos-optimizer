import Foundation
import Combine
import AppKit
import ServiceManagement
import OSLog

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    static let shared = LaunchAtLoginStore()

    @Published private(set) var isEnabled: Bool = false
    @Published var statusMessage: String?

    /// After login, run light optimize (e.g. stop TM backup). Soft Turbo state is separate.
    @Published var optimizeOnLaunch: Bool {
        didSet { UserDefaults.standard.set(optimizeOnLaunch, forKey: Keys.optimizeOnLaunch) }
    }

    private enum Keys {
        static let optimizeOnLaunch = "fg.launch.optimizeOnLaunch"
    }

    private let log = Logger(subsystem: "com.fgmacos.optimizer", category: "launch")

    private init() {
        optimizeOnLaunch = UserDefaults.standard.object(forKey: Keys.optimizeOnLaunch) as? Bool ?? true
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        switch status {
        case .enabled, .notRegistered:
            statusMessage = nil
        case .notFound:
            statusMessage = "Launch service unavailable"
        case .requiresApproval:
            statusMessage = "Allow in System Settings → Login Items"
        @unknown default:
            statusMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                log.info("Registered launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                log.info("Unregistered launch at login")
            }
        } catch {
            statusMessage = error.localizedDescription
            log.error("Launch at login error: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            openLoginItemsSettings()
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func openLoginItemsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.users"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
