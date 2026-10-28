import Foundation

actor SystemCleaner {
    /// Exact folder names OR prefix matches under ~/Library/Caches (safe allow-list only).
    private let allowedExact: Set<String> = [
        "Homebrew",
        "pip",
        "CocoaPods",
        "GeoServices",
        "com.apple.helpd",
        "com.spotify.client",
        "com.docker.docker",
        "com.microsoft.VSCode",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.apple.Music",
        "com.apple.maps"
    ]

    private let allowedPrefixes: [String] = [
        "com.apple.Safari",
        "com.apple.WebKit",
        "com.google.Chrome",
        "com.spotify.",
        "com.docker.",
        "com.microsoft.VSCode",
        "org.mozilla.firefox",
        "Homebrew"
    ]

    private let blockedSubstrings: [String] = [
        "CloudDocs",
        "FamilyCircle",
        "accountsd",
        "Keychain",
        "Cookies",
        "Credentials",
        "CloudKit",
        "Passwords"
    ]

    private let maxBytesToDelete: UInt64 = 2 * 1024 * 1024 * 1024
    private let maxFiles = 8_000

    func runDeepClean() async -> CleanResult {
        let cacheBytes = await clearSafeCaches()
        AppLog.cleaner.info("Cache clean freed \(cacheBytes, privacy: .public) bytes")
        let dns = await flushDNS()
        AppLog.cleaner.info("DNS flush ok=\(dns, privacy: .public)")
        let docker = await pruneDockerVolumes()
        let dockerMsg = docker.message ?? "-"
        AppLog.cleaner.info("Docker prune ok=\(docker.pruned, privacy: .public) msg=\(dockerMsg, privacy: .public)")

        return CleanResult(
            cacheBytesFreed: cacheBytes,
            dnsFlushed: dns,
            dockerPruned: docker.pruned,
            dockerMessage: docker.message
        )
    }

    /// Runs `purge` to drop file-backed disk cache pages (needs admin).
    /// Note: macOS will refill cache as you use apps — high RAM use alone is normal.
    func purgeInactiveMemory() async -> CleanResult {
        let before = MachMemory.sample()?.availableBytes ?? 0
        let result = await PrivilegedRunner.run(
            "/usr/sbin/purge",
            args: [],
            needsAdmin: true,
            reason: "Free RAM — purge reclaimable disk cache."
        )
        // Give kernel a moment to reclaim
        try? await Task.sleep(nanoseconds: 700_000_000)
        let after = MachMemory.sample()?.availableBytes ?? before
        return CleanResult(
            cacheBytesFreed: 0,
            dnsFlushed: false,
            dockerPruned: false,
            dockerMessage: nil,
            memoryPurged: result.ok,
            availableBefore: before,
            availableAfter: after
        )
    }

    private func clearSafeCaches() async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
                let fm = FileManager.default
                guard let children = try? fm.contentsOfDirectory(atPath: root) else {
                    cont.resume(returning: 0)
                    return
                }

                var freed: UInt64 = 0
                var files = 0

                for name in children {
                    if freed >= self.maxBytesToDelete || files >= self.maxFiles { break }
                    guard self.isAllowedCache(name) else { continue }
                    let path = (root as NSString).appendingPathComponent(name)
                    let result = self.deleteContents(
                        at: path,
                        remainingBytes: self.maxBytesToDelete - freed,
                        remainingFiles: self.maxFiles - files
                    )
                    freed += result.bytes
                    files += result.files
                }

                cont.resume(returning: freed)
            }
        }
    }

    private func isAllowedCache(_ name: String) -> Bool {
        for b in blockedSubstrings where name.localizedCaseInsensitiveContains(b) {
            return false
        }
        if allowedExact.contains(name) { return true }
        for prefix in allowedPrefixes where name.hasPrefix(prefix) {
            return true
        }
        return false
    }

    private func deleteContents(at path: String, remainingBytes: UInt64, remainingFiles: Int) -> (bytes: UInt64, files: Int) {
        let fm = FileManager.default
        var bytes: UInt64 = 0
        var files = 0

        guard let enumerator = fm.enumerator(atPath: path) else { return (0, 0) }
        var toDelete: [String] = []

        while let relative = enumerator.nextObject() as? String {
            if files >= remainingFiles || bytes >= remainingBytes { break }
            // Never delete the root folder itself; skip very new files (< 1 hour) to reduce races
            let full = (path as NSString).appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let attrs = try? fm.attributesOfItem(atPath: full) {
                // Skip only very fresh files (60s) to avoid races — not a full hour
                if let modified = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(modified) < 60 {
                    continue
                }
                if let size = attrs[.size] as? UInt64 {
                    bytes += size
                }
            }
            files += 1
            toDelete.append(full)
        }

        for file in toDelete {
            try? fm.removeItem(atPath: file)
        }
        return (bytes, files)
    }

    private func flushDNS() async -> Bool {
        // One elevation for both steps — avoids a second password sheet mid-clean.
        let result = await PrivilegedRunner.runAdminScript(
            "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder",
            reason: "Flush DNS cache."
        )
        return result.ok
    }

    private func pruneDockerVolumes() async -> (pruned: Bool, message: String?) {
        guard let dockerPath = resolveDocker() else {
            return (false, "Docker not found")
        }
        // Only prune dangling volumes — never wipe named volumes in use
        let result = await PrivilegedRunner.run(
            dockerPath,
            args: ["volume", "prune", "-f"],
            needsAdmin: false
        )
        if result.ok {
            return (true, nil)
        }
        return (false, "Docker prune skipped")
    }

    private func resolveDocker() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
