import Foundation

/// Aggregates safe junk categories for the Smart Care hero flow.
actor SmartCareEngine {
    func scan(includeDev: Bool = true) async -> [CleanItem] {
        var items: [CleanItem] = []

        let caches = await measureAllowListedCaches()
        if caches.bytes > 0 {
            items.append(CleanItem(
                id: "smart.caches",
                category: .smartCare,
                title: "App caches (allow-listed)",
                subtitle: "Safe browser/dev caches under ~/Library/Caches",
                bytes: caches.bytes,
                paths: caches.paths,
                risk: .safeJunk,
                disposal: .delete
            ))
        }

        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        let trashBytes = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: trashPath))
        if trashBytes > 0 {
            // Empty trash = delete contents, not the .Trash folder.
            let children = (try? FileManager.default.contentsOfDirectory(atPath: trashPath)) ?? []
            let paths = children.map { (trashPath as NSString).appendingPathComponent($0) }
                .filter { CleanSafety.assertSafeToRemove(path: $0) }
            if !paths.isEmpty {
                items.append(CleanItem(
                    id: "smart.trash",
                    category: .smartCare,
                    title: "Empty Trash",
                    subtitle: "\(paths.count) items in Trash",
                    bytes: trashBytes,
                    paths: paths,
                    risk: .review,
                    disposal: .delete
                ))
            }
        }

        // Free RAM is a toggle item (no paths) — handled specially by UI/AppState.
        items.append(CleanItem(
            id: "smart.ram",
            category: .smartCare,
            title: "Free RAM (purge)",
            subtitle: "Admin once · reclaimable disk cache",
            bytes: 0,
            paths: [],
            risk: .review,
            disposal: .delete,
            selected: false,
            meta: ["action": "purge"]
        ))

        if includeDev {
            let dev = await DevCleanupPack().scan()
            for d in dev where d.risk == .safeJunk {
                var copy = d
                // Keep ids unique under smart care
                items.append(CleanItem(
                    id: "smart.\(d.id)",
                    category: .smartCare,
                    title: d.title,
                    subtitle: d.subtitle,
                    bytes: d.bytes,
                    paths: d.paths,
                    risk: d.risk,
                    disposal: d.disposal,
                    selected: d.selected
                ))
                _ = copy
            }
        }

        return items.sorted { $0.bytes > $1.bytes }
    }

    private func measureAllowListedCaches() async -> (bytes: UInt64, paths: [String]) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
                let allowedExact: Set<String> = [
                    "Homebrew", "pip", "CocoaPods", "GeoServices",
                    "com.apple.helpd", "com.spotify.client", "com.docker.docker",
                    "com.microsoft.VSCode", "com.google.Chrome", "org.mozilla.firefox",
                    "com.apple.Safari", "com.apple.Music", "com.apple.maps"
                ]
                let allowedPrefixes = [
                    "com.apple.Safari", "com.apple.WebKit", "com.google.Chrome",
                    "com.spotify.", "com.docker.", "com.microsoft.VSCode",
                    "org.mozilla.firefox", "Homebrew"
                ]
                let blocked = ["CloudDocs", "Keychain", "Cookies", "Credentials", "CloudKit", "Passwords"]
                let fm = FileManager.default
                guard let children = try? fm.contentsOfDirectory(atPath: root) else {
                    cont.resume(returning: (0, []))
                    return
                }
                var paths: [String] = []
                var total: UInt64 = 0
                for name in children {
                    if blocked.contains(where: { name.localizedCaseInsensitiveContains($0) }) { continue }
                    let ok = allowedExact.contains(name) || allowedPrefixes.contains(where: { name.hasPrefix($0) })
                    guard ok else { continue }
                    let path = (root as NSString).appendingPathComponent(name)
                    guard CleanSafety.assertSafeToRemove(path: path) else { continue }
                    let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
                    if size > 0 {
                        paths.append(path)
                        total += size
                    }
                }
                cont.resume(returning: (total, paths))
            }
        }
    }
}
