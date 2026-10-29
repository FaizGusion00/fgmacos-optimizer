import Foundation
import AppKit

struct InstalledApp: Identifiable, Equatable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var bundleID: String?
    var bytes: UInt64
}

actor AppUninstaller {
    func listApps() async -> [InstalledApp] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var apps: [InstalledApp] = []
                let roots = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
                let fm = FileManager.default
                for root in roots {
                    guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
                    for name in children where name.hasSuffix(".app") {
                        let path = (root as NSString).appendingPathComponent(name)
                        let bundle = Bundle(path: path)
                        let bid = bundle?.bundleIdentifier
                        let display = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                            ?? name.replacingOccurrences(of: ".app", with: "")
                        if CleanSafety.isProtectedApp(bundleID: bid, name: display) { continue }
                        if ProtectionGuard.isBundleProtected(bid) { continue }
                        if ProtectionGuard.isPathProtected(path) { continue }
                        if bid?.hasPrefix("com.apple.") == true { continue }
                        let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
                        apps.append(InstalledApp(name: display, path: path, bundleID: bid, bytes: size))
                    }
                }
                cont.resume(returning: apps.sorted { $0.bytes > $1.bytes })
            }
        }
    }

    func leftovers(for app: InstalledApp) async -> [CleanItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [CleanItem] = []
                let home = NSHomeDirectory()
                let lib = (home as NSString).appendingPathComponent("Library")
                let name = app.name
                let bid = app.bundleID ?? ""

                items.append(CleanItem(
                    id: "app.bundle",
                    category: .uninstaller,
                    title: "\(name).app",
                    subtitle: app.path,
                    bytes: app.bytes,
                    paths: [app.path],
                    risk: .destructive,
                    disposal: .trash,
                    selected: true
                ))

                let searchRoots: [(String, String)] = [
                    ("Preferences", (lib as NSString).appendingPathComponent("Preferences")),
                    ("Caches", (lib as NSString).appendingPathComponent("Caches")),
                    ("Application Support", (lib as NSString).appendingPathComponent("Application Support")),
                    ("Logs", (lib as NSString).appendingPathComponent("Logs")),
                    ("Saved State", (lib as NSString).appendingPathComponent("Saved Application State")),
                    ("LaunchAgents", (lib as NSString).appendingPathComponent("LaunchAgents")),
                    ("Containers", (lib as NSString).appendingPathComponent("Containers")),
                    ("Group Containers", (lib as NSString).appendingPathComponent("Group Containers"))
                ]

                let fm = FileManager.default
                for (label, root) in searchRoots {
                    guard let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
                    for child in children {
                        let match: Bool
                        if !bid.isEmpty {
                            match = child.localizedCaseInsensitiveContains(bid) || child.localizedCaseInsensitiveContains(name)
                        } else {
                            match = child.localizedCaseInsensitiveContains(name)
                        }
                        guard match else { continue }
                        let path = (root as NSString).appendingPathComponent(child)
                        guard CleanSafety.assertSafeToRemove(path: path) else { continue }
                        if CleanSafety.isBlocked(path: path) { continue }
                        let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
                        items.append(CleanItem(
                            id: "leftover.\(label).\(child)",
                            category: .uninstaller,
                            title: "\(label)/\(child)",
                            subtitle: path,
                            bytes: size,
                            paths: [path],
                            risk: .review,
                            disposal: .trash,
                            selected: label != "Containers" && label != "Group Containers"
                        ))
                    }
                }
                cont.resume(returning: items)
            }
        }
    }
}
