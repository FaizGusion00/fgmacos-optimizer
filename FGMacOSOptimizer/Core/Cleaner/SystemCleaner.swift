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

    func flushDNSOnly() async -> CleanResult {
        let ok = await flushDNS()
        return CleanResult(cacheBytesFreed: 0, dnsFlushed: ok, dockerPruned: false, dockerMessage: nil)
    }

    func cleanBucket(_ bucket: StorageBucket) async -> CleanResult {
        switch bucket {
        case .caches:
            let bytes = await clearSafeCaches()
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .downloads:
            let bytes = await clearDirectoryContents(
                path: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"),
                maxBytes: 4 * 1024 * 1024 * 1024,
                maxFiles: 20_000,
                skipNewerThan: 3600
            )
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .derivedData:
            let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let bytes = await clearDirectoryContents(
                path: path,
                maxBytes: 20 * 1024 * 1024 * 1024,
                maxFiles: 100_000,
                skipNewerThan: 30
            )
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .docker:
            let docker = await pruneDockerVolumes()
            return CleanResult(
                cacheBytesFreed: 0,
                dnsFlushed: false,
                dockerPruned: docker.pruned,
                dockerMessage: docker.message
            )
        case .trash:
            let path = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
            let bytes = await emptyTrash(at: path)
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        }
    }

    private func clearDirectoryContents(
        path: String,
        maxBytes: UInt64,
        maxFiles: Int,
        skipNewerThan: TimeInterval
    ) async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let result = self.deleteContents(
                    at: path,
                    remainingBytes: maxBytes,
                    remainingFiles: maxFiles,
                    skipNewerThan: skipNewerThan
                )
                cont.resume(returning: result.bytes)
            }
        }
    }

    private func emptyTrash(at path: String) async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let children = try? fm.contentsOfDirectory(atPath: path) else {
                    cont.resume(returning: 0)
                    return
                }
                var freed: UInt64 = 0
                for name in children {
                    let full = (path as NSString).appendingPathComponent(name)
                    let size = Self.itemSize(full)
                    try? fm.removeItem(atPath: full)
                    freed += size
                }
                cont.resume(returning: freed)
            }
        }
    }

    private static func itemSize(_ path: String) -> UInt64 {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return 0 }
        if let size = attrs[.size] as? UInt64 { return size }
        return 0
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
                        remainingFiles: self.maxFiles - files,
                        skipNewerThan: 60
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

    private func deleteContents(
        at path: String,
        remainingBytes: UInt64,
        remainingFiles: Int,
        skipNewerThan: TimeInterval
    ) -> (bytes: UInt64, files: Int) {
        let fm = FileManager.default
        var bytes: UInt64 = 0
        var files = 0

        guard let enumerator = fm.enumerator(atPath: path) else { return (0, 0) }
        var toDelete: [String] = []

        while let relative = enumerator.nextObject() as? String {
            if files >= remainingFiles || bytes >= remainingBytes { break }
            let full = (path as NSString).appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let attrs = try? fm.attributesOfItem(atPath: full) {
                if let modified = attrs[.modificationDate] as? Date,
                   Date().timeIntervalSince(modified) < skipNewerThan {
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
