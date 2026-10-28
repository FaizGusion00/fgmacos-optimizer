import Foundation
import AppKit

/// Apps / processes that must never be killed by Watchdog.
final class WhitelistStore: ObservableObject {
    @Published private(set) var bundleIDs: Set<String>
    @Published private(set) var processNames: Set<String>

    private let defaultsKey = "fg.whitelist.bundleIDs"
    private let namesKey = "fg.whitelist.processNames"

    static let defaults: Set<String> = [
        "com.apple.finder",
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.docker.docker",
        "com.apple.systempreferences",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.dock"
    ]

    static let defaultNames: Set<String> = [
        "Cursor", "Terminal", "iTerm2", "Xcode",
        "Docker", "Docker Desktop", "WindowServer",
        "kernel_task", "loginwindow", "Finder"
    ]

    static let protectedNamePrefixes: [String] = [
        "Cursor", "Docker", "WindowServer", "kernel_task",
        "opendirectoryd", "syspolicyd", "trustd", "mds", "mdworker", "FGMacOS"
    ]

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let savedNames = UserDefaults.standard.stringArray(forKey: namesKey) ?? []
        bundleIDs = Self.defaults.union(saved)
        processNames = Self.defaultNames.union(savedNames)
    }

    func isProtected(bundleID: String?, name: String) -> Bool {
        if let bundleID {
            if bundleIDs.contains(bundleID) { return true }
            if bundleID.hasPrefix("com.apple.") { return true }
            if bundleID == "com.fgmacos.optimizer" { return true }
        }
        if processNames.contains(name) { return true }
        for prefix in Self.protectedNamePrefixes where name.hasPrefix(prefix) || name.contains(prefix) {
            return true
        }
        return false
    }

    func isKillCandidate(bundleID: String?, name: String, runningApp: NSRunningApplication?) -> Bool {
        if isProtected(bundleID: bundleID, name: name) { return false }
        guard let runningApp else { return false }
        if runningApp.activationPolicy == .regular { return true }
        if let bid = runningApp.bundleIdentifier, !bid.hasPrefix("com.apple.") {
            return true
        }
        return false
    }

    func add(bundleID: String) {
        bundleIDs.insert(bundleID)
        persist()
    }

    func remove(bundleID: String) {
        guard !Self.defaults.contains(bundleID) else { return }
        bundleIDs.remove(bundleID)
        persist()
    }

    private func persist() {
        let custom = bundleIDs.subtracting(Self.defaults)
        UserDefaults.standard.set(Array(custom), forKey: defaultsKey)
        let customNames = processNames.subtracting(Self.defaultNames)
        UserDefaults.standard.set(Array(customNames), forKey: namesKey)
    }
}
