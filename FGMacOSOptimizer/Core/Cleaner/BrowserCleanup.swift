import Foundation

actor BrowserCleanup {
    func scan(includeHistory: Bool) async -> [CleanItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [CleanItem] = []
                let home = NSHomeDirectory()
                let lib = (home as NSString).appendingPathComponent("Library")

                // Safari caches only — never Cookies / Passwords / LocalStorage
                let safariCaches = [
                    (lib as NSString).appendingPathComponent("Caches/com.apple.Safari"),
                    (lib as NSString).appendingPathComponent("Caches/com.apple.WebKit.WebContent"),
                    (lib as NSString).appendingPathComponent("Caches/WebKit")
                ]
                for path in safariCaches {
                    Self.appendCacheItem(path: path, title: "Safari cache", into: &items, idPrefix: "safari")
                }

                // Chrome
                let chromeBase = (lib as NSString).appendingPathComponent("Application Support/Google/Chrome/Default")
                for name in ["Cache", "Code Cache", "GPUCache"] {
                    let path = (chromeBase as NSString).appendingPathComponent(name)
                    Self.appendCacheItem(path: path, title: "Chrome \(name)", into: &items, idPrefix: "chrome")
                }
                if includeHistory {
                    let hist = (chromeBase as NSString).appendingPathComponent("History")
                    if FileManager.default.fileExists(atPath: hist), CleanSafety.assertSafeToRemove(path: hist) {
                        // Still skip if somehow cookie-like — History only
                        items.append(CleanItem(
                            id: "chrome.history",
                            category: .browser,
                            title: "Chrome History",
                            subtitle: "Quit Chrome first · does not remove cookies",
                            bytes: CleanSafety.directoryOrFileSize(URL(fileURLWithPath: hist)),
                            paths: [hist],
                            risk: .destructive,
                            disposal: .delete,
                            selected: false
                        ))
                    }
                }

                // Firefox
                let ffProfiles = (lib as NSString).appendingPathComponent("Application Support/Firefox/Profiles")
                if let profiles = try? FileManager.default.contentsOfDirectory(atPath: ffProfiles) {
                    for profile in profiles {
                        let cache2 = ((ffProfiles as NSString).appendingPathComponent(profile) as NSString).appendingPathComponent("cache2")
                        Self.appendCacheItem(path: cache2, title: "Firefox cache (\(profile))", into: &items, idPrefix: "ff")
                    }
                }

                cont.resume(returning: items.filter { $0.bytes > 0 || $0.id.contains("history") })
            }
        }
    }

    private static func appendCacheItem(path: String, title: String, into items: inout [CleanItem], idPrefix: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard CleanSafety.assertSafeToRemove(path: path) else { return }
        if path.localizedCaseInsensitiveContains("Cookie") { return }
        if path.localizedCaseInsensitiveContains("Password") { return }
        if path.localizedCaseInsensitiveContains("LocalStorage") { return }
        let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
        guard size > 0 else { return }
        items.append(CleanItem(
            id: "\(idPrefix).\(path.hashValue)",
            category: .browser,
            title: title,
            subtitle: path,
            bytes: size,
            paths: [path],
            risk: .safeJunk,
            disposal: .delete,
            selected: true
        ))
    }
}
