#if DEBUG
import AppKit
import Foundation

/// DEBUG-only test harness. Compiled out of Release.
/// Enable with `defaults write com.fgmacos.optimizer fg.debug.automation -bool true`.
/// Drive with:  echo "<command>" > /tmp/fgopt-debug/cmd.txt   → result in /tmp/fgopt-debug/result.json
/// Commands: state · snapshot · popover.open · popover.close · quickOptimize · turbo.toggle
///           focus.coding · focus.off · cleaner.open · cleaner.close · freeRAM
@MainActor
final class DebugAutomation {
    static let shared = DebugAutomation()

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "fg.debug.automation") }
    /// NSAlert confirms return "Continue" without showing (tests can't click).
    static var autoConfirm: Bool { isEnabled && UserDefaults.standard.bool(forKey: "fg.debug.autoConfirm") }
    /// Privileged commands report "skipped" instead of raising the SecurityAgent sheet.
    static var skipAdmin: Bool { isEnabled && UserDefaults.standard.bool(forKey: "fg.debug.skipAdmin") }

    private let dir = URL(fileURLWithPath: "/tmp/fgopt-debug", isDirectory: true)
    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private weak var delegate: AppDelegate?

    func start(delegate: AppDelegate) {
        guard Self.isEnabled else { return }
        self.delegate = delegate
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirFD = open(dir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.drain() }
        src.resume()
        source = src
        AppLog.lifeFile("debug automation armed at \(dir.path)")
        drain()
    }

    private func drain() {
        let cmdURL = dir.appendingPathComponent("cmd.txt")
        guard let raw = try? String(contentsOf: cmdURL, encoding: .utf8) else { return }
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A shell `>` creates the file empty first — leave it for the write event that follows.
        guard !command.isEmpty else { return }
        try? FileManager.default.removeItem(at: cmdURL)
        AppLog.lifeFile("debug cmd: \(command)")
        Task { @MainActor in
            let result = await run(command)
            write(result: result, for: command)
        }
    }

    private func run(_ command: String) async -> [String: Any] {
        guard let delegate else { return ["error": "no delegate"] }
        let app = delegate.appState
        switch command {
        case "state":
            return state()
        case "popover.open":
            delegate.showPopoverFromStatusItem()
            try? await Task.sleep(nanoseconds: 900_000_000)
            return state()
        case "popover.close":
            delegate.closePopover()
            try? await Task.sleep(nanoseconds: 600_000_000)
            return state()
        case "snapshot":
            var out: [String: Any] = [:]
            if let view = delegate.debugPopoverView, delegate.isPopoverShown {
                out["popover"] = snapshot(view: view, name: "popover.png")
            }
            if let win = CleanerWindowController.debugWindow, let view = win.contentView {
                out["cleaner"] = snapshot(view: view, name: "cleaner.png")
            }
            return out.merging(state()) { a, _ in a }
        case "quickOptimize":
            app.speedBoost()
            return state()
        case "turbo.toggle":
            app.toggleTurbo()
            return state()
        case "focus.coding":
            app.applyFocus(.coding)
            return state()
        case "focus.off":
            app.applyFocus(.off)
            return state()
        case "cleaner.open":
            CleanerWindowController.show(showIntroIfNeeded: false)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return state()
        case "cleaner.close":
            CleanerWindowController.debugWindow?.performClose(nil)
            try? await Task.sleep(nanoseconds: 600_000_000)
            return state()
        case "freeRAM":
            app.freeRAM()
            return state()
        default:
            return ["error": "unknown command \(command)"]
        }
    }

    private func state() -> [String: Any] {
        guard let delegate else { return ["error": "no delegate"] }
        let app = delegate.appState
        var s: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "popoverShown": delegate.isPopoverShown,
            "popoverBehavior": delegate.debugPopoverBehavior,
            "isOptimizing": app.isOptimizing,
            "operationStatus": app.operationStatus ?? "",
            "operationDetail": app.operationDetail ?? "",
            "turboActive": app.isTurboActive,
            "turboDetail": app.turbo.lastVerifiedDetail,
            "exclusionCount": app.turbo.exclusionCount,
            "volumeIndexingDisabled": app.turbo.volumeIndexingDisabled,
            "focus": app.focus.active.rawValue,
            "keepInMenuBar": FeatureSettingsStore.shared.keepInMenuBar,
            "cleanerExists": CleanerWindowController.exists,
            "permissionsExists": PermissionsWindowController.exists,
            "authUnlocked": SessionAuth.shared.isUnlocked,
            "authBusy": SessionAuth.shared.isBusy,
            "cleanerScanning": CleanerStore.shared.isScanning,
            "cleanerCleaning": CleanerStore.shared.isCleaning,
            "cleanerItems": CleanerStore.shared.items.count,
            "cleanerSelected": CleanerStore.shared.items.filter(\.selected).map(\.title),
            "cleanerUnselected": CleanerStore.shared.items.filter { !$0.selected }.map(\.title),
            "memoryPressure": app.displayMetrics.memoryPressure.title,
            "diskFreeGB": Double(app.displayMetrics.diskAvailableBytes) / 1_073_741_824.0,
            "urgent": String(describing: app.displayMetrics.urgentCondition.map { "\($0)" } ?? "none")
        ]
        if let r = app.lastReport {
            s["lastReportTitle"] = r.title
            s["lastReportSummary"] = r.summaryLine
            s["lastReportDetail"] = r.detail ?? ""
        }
        if let e = app.actionError { s["actionError"] = e }
        return s
    }

    private func snapshot(view: NSView, name: String) -> String {
        let url = dir.appendingPathComponent(name)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return "no rep" }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return "no png" }
        do {
            try png.write(to: url)
            return url.path
        } catch {
            return "write failed: \(error.localizedDescription)"
        }
    }

    private func write(result: [String: Any], for command: String) {
        var payload = result
        payload["command"] = command
        payload["at"] = ISO8601DateFormatter().string(from: Date())
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        try? data.write(to: dir.appendingPathComponent("result.json"), options: .atomic)
    }
}
#endif
