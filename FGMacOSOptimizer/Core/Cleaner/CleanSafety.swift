import Foundation

/// Central blocklist / path guards for all Cleaner deletes.
enum CleanSafety {
    static let blockedNameTokens: [String] = [
        "Keychain", "Cookies", "Passwords", "Credentials", "CloudKit",
        "CloudDocs", "Photos Library.photoslibrary", "LocalStorage"
    ]

    static func isBlocked(path: String) -> Bool {
        let p = path
        if p.hasPrefix("/System/") || p.hasPrefix("/usr/") || p.hasPrefix("/bin/") || p.hasPrefix("/sbin/") {
            return true
        }
        if p.hasPrefix("/Library/Apple/") { return true }
        if p.localizedCaseInsensitiveContains("Mobile Documents") { return true }
        if p.localizedCaseInsensitiveContains("Photos Library.photoslibrary") { return true }
        // Block sensitive name tokens in the last path components (not whole tree blindly).
        let parts = p.split(separator: "/").suffix(3).map(String.init)
        for part in parts {
            for token in blockedNameTokens where part.localizedCaseInsensitiveContains(token) {
                return true
            }
        }
        return false
    }

    static func assertSafeToRemove(path: String) -> Bool {
        if path.isEmpty { return false }
        if path == "/" || path == NSHomeDirectory() { return false }
        let trashRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        // Never delete the Trash folder itself; children OK for Empty Trash.
        if path == trashRoot || path.hasSuffix("/.Trash") { return false }
        if isBlocked(path: path) { return false }
        if ProtectionGuard.isPathProtected(path) { return false }
        let homeLib = (NSHomeDirectory() as NSString).appendingPathComponent("Library")
        if path == homeLib || path == "/Applications" { return false }
        return true
    }

    static func isProtectedApp(bundleID: String?, name: String) -> Bool {
        if ProtectionGuard.isBundleProtected(bundleID) { return true }
        if let bundleID {
            if bundleID == "com.fgmacos.optimizer" { return true }
            if bundleID.hasPrefix("com.apple.") { return true }
        }
        let protected = ["Finder", "Terminal", "WindowServer", "kernel_task", "Cursor", "Xcode", "Docker"]
        return protected.contains(where: { name.localizedCaseInsensitiveContains($0) })
    }

    @discardableResult
    static func trash(_ url: URL) -> (ok: Bool, bytes: UInt64, trashURL: URL?) {
        guard assertSafeToRemove(path: url.path) else { return (false, 0, nil) }
        let size = directoryOrFileSize(url)
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return (true, size, resulting as URL?)
        } catch {
            return (false, 0, nil)
        }
    }

    @discardableResult
    static func delete(_ url: URL) -> (ok: Bool, bytes: UInt64) {
        guard assertSafeToRemove(path: url.path) else { return (false, 0) }
        let size = directoryOrFileSize(url)
        do {
            try FileManager.default.removeItem(at: url)
            return (true, size)
        } catch {
            return (false, 0)
        }
    }

    static func directoryOrFileSize(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return attrs?[.size] as? UInt64 ?? 0
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: UInt64 = 0
        var n = 0
        while let item = enumerator.nextObject() as? URL {
            n += 1
            if n > 80_000 { break }
            guard let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let size = vals.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        CleanResult.formatBytes(bytes)
    }
}
