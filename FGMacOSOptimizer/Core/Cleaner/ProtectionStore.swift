import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// User whitelist: folders/apps never scanned or cleaned.
@MainActor
final class ProtectionStore: ObservableObject {
    static let shared = ProtectionStore()

    @Published private(set) var paths: [String]
    @Published private(set) var bundleIDs: [String]

    private enum Keys {
        static let paths = "fg.protection.paths.v1"
        static let bundles = "fg.protection.bundles.v1"
    }

    private init() {
        paths = UserDefaults.standard.stringArray(forKey: Keys.paths) ?? []
        bundleIDs = UserDefaults.standard.stringArray(forKey: Keys.bundles) ?? []
    }

    func addPath(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        guard !normalized.isEmpty, !paths.contains(normalized) else { return }
        paths.append(normalized)
        paths.sort()
        persist()
    }

    func removePath(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    func addBundleID(_ id: String) {
        guard !id.isEmpty, !bundleIDs.contains(id) else { return }
        bundleIDs.append(id)
        bundleIDs.sort()
        persist()
    }

    func removeBundleID(_ id: String) {
        bundleIDs.removeAll { $0 == id }
        persist()
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Protect"
        panel.message = "Folders on this list are never scanned or cleaned."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addPath(url.path)
        }
    }

    func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Protect"
        panel.message = "Apps on this list are hidden from Uninstaller leftovers targeting."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bid = Bundle(url: url)?.bundleIdentifier {
                addBundleID(bid)
            }
            addPath(url.path)
        }
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: Keys.paths)
        UserDefaults.standard.set(bundleIDs, forKey: Keys.bundles)
    }
}

/// Thread-safe path checks for scanners (reads UserDefaults).
enum ProtectionGuard {
    private static let pathsKey = "fg.protection.paths.v1"
    private static let bundlesKey = "fg.protection.bundles.v1"

    static func isPathProtected(_ path: String) -> Bool {
        let protected = UserDefaults.standard.stringArray(forKey: pathsKey) ?? []
        let standardized = (path as NSString).standardizingPath
        for raw in protected {
            let p = (raw as NSString).standardizingPath
            if standardized == p { return true }
            let prefix = p.hasSuffix("/") ? p : p + "/"
            if standardized.hasPrefix(prefix) { return true }
        }
        return false
    }

    static func isBundleProtected(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        let protected = UserDefaults.standard.stringArray(forKey: bundlesKey) ?? []
        return protected.contains(bundleID)
    }

    static func filterItems(_ items: [CleanItem]) -> [CleanItem] {
        items.compactMap { item in
            let kept = item.paths.filter { !isPathProtected($0) && CleanSafety.assertSafeToRemove(path: $0) }
            // Keep special actions (no paths) like Free RAM.
            if item.paths.isEmpty { return item }
            guard !kept.isEmpty else { return nil }
            var copy = item
            if kept.count != item.paths.count {
                copy = CleanItem(
                    id: item.id,
                    category: item.category,
                    title: item.title,
                    subtitle: item.subtitle + " · protected paths skipped",
                    bytes: kept.reduce(0) { $0 + CleanSafety.directoryOrFileSize(URL(fileURLWithPath: $1)) },
                    paths: kept,
                    risk: item.risk,
                    disposal: item.disposal,
                    selected: item.selected,
                    meta: item.meta
                )
            }
            return copy
        }
    }
}
