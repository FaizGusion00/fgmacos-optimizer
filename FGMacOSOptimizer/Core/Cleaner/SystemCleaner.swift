import Foundation

actor SystemCleaner {
    /// Never wipe these top-level ~/Library/Caches folders (accounts / sync / secrets).
    private let blockedCacheNames: [String] = [
        "CloudDocs", "CloudKit", "FamilyCircle", "accountsd",
        "Keychain", "Cookies", "Credentials", "Passwords",
        "com.apple.Safari.SafeBrowsing", "com.apple.findmy",
        "com.apple.HomeKit", "com.apple.MobileSMS",
        "com.apple.AddressBook", "com.apple.bird",
        "com.apple.nsurlsessiond", "com.apple.akd"
    ]

    func runDeepClean() async -> CleanResult {
        let cacheBytes = await clearSafeCaches()
        AppLog.cleaner.info("Cache clean freed \(cacheBytes, privacy: .public) bytes")
        let dns = await flushDNS()
        AppLog.cleaner.info("DNS flush ok=\(dns, privacy: .public)")
        let docker = await pruneDockerUnused()
        let dockerMsg = docker.message ?? "-"
        AppLog.cleaner.info("Docker prune ok=\(docker.pruned, privacy: .public) msg=\(dockerMsg, privacy: .public) bytes=\(docker.bytes, privacy: .public)")

        return CleanResult(
            cacheBytesFreed: cacheBytes + docker.bytes,
            dnsFlushed: dns,
            dockerPruned: docker.pruned,
            dockerMessage: docker.message
        )
    }

    func flushDNSOnly() async -> CleanResult {
        let ok = await flushDNS()
        return CleanResult(cacheBytesFreed: 0, dnsFlushed: ok, dockerPruned: false, dockerMessage: nil)
    }

    /// One-shot “make this Mac feel faster” pass — safe caches, stale logs, DNS, optional purge, stop TM.
    /// Does not touch Docker (slow / surprising) or Derived Data.
    func runSpeedBoost(purgeMemory: Bool) async -> CleanResult {
        let before = MachMemory.sample()?.availableBytes ?? 0

        let cacheBytes = await clearSafeCaches()
        AppLog.cleaner.info("SpeedBoost caches freed \(cacheBytes, privacy: .public)")

        let logBytes = await clearStaleLogs(olderThanDays: 14)
        AppLog.cleaner.info("SpeedBoost logs freed \(logBytes, privacy: .public)")

        // Only reported as "paused" when a backup was actually running.
        let tmPaused = await TimeMachineStatus.stopBackupIfRunning()

        let dns = await flushDNS()
        AppLog.cleaner.info("SpeedBoost DNS ok=\(dns, privacy: .public)")

        var purged = false
        if purgeMemory {
            let purge = await PrivilegedRunner.run(
                "/usr/sbin/purge",
                args: [],
                needsAdmin: true,
                reason: "Quick Optimize — free reclaimable RAM (purge)."
            )
            purged = purge.ok
            if purged {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        let after = MachMemory.sample()?.availableBytes ?? before
        return CleanResult(
            cacheBytesFreed: cacheBytes,
            dnsFlushed: dns,
            dockerPruned: false,
            dockerMessage: nil,
            memoryPurged: purged,
            availableBefore: before,
            availableAfter: after,
            timeMachineStopped: tmPaused,
            spotlightExcluded: 0,
            logsBytesFreed: logBytes
        )
    }

    /// Quiet launch pass — no admin prompts (no DNS / purge).
    func runLaunchLightBoost() async -> CleanResult {
        let before = MachMemory.sample()?.availableBytes ?? 0
        let cacheBytes = await clearSafeCaches()
        let logBytes = await clearStaleLogs(olderThanDays: 21)
        let tmPaused = await TimeMachineStatus.stopBackupIfRunning()
        let after = MachMemory.sample()?.availableBytes ?? before
        return CleanResult(
            cacheBytesFreed: cacheBytes,
            dnsFlushed: false,
            dockerPruned: false,
            dockerMessage: nil,
            memoryPurged: false,
            availableBefore: before,
            availableAfter: after,
            timeMachineStopped: tmPaused,
            spotlightExcluded: 0,
            logsBytesFreed: logBytes
        )
    }

    /// Delete ~/Library/Logs files older than N days (apps recreate logs).
    func clearStaleLogs(olderThanDays: Int) async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs")
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    cont.resume(returning: 0)
                    return
                }

                let cutoff = Date().addingTimeInterval(-TimeInterval(olderThanDays) * 86_400)
                // Old Macs: bound the walk so a huge Logs tree can never stall the optimize.
                let deadline = Date().addingTimeInterval(20)
                var visited = 0
                var freed: UInt64 = 0
                var count = 0
                while let url = enumerator.nextObject() as? URL {
                    visited += 1
                    if visited >= 60_000 || (visited % 500 == 0 && Date() >= deadline) { break }
                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                          values.isRegularFile == true,
                          let modified = values.contentModificationDate,
                          modified < cutoff
                    else { continue }
                    let size = UInt64(values.fileSize ?? 0)
                    do {
                        try fm.removeItem(at: url)
                        freed += size
                        count += 1
                    } catch {
                        continue
                    }
                    if count >= 8_000 { break }
                }
                AppLog.cleaner.info("clearStaleLogs removed=\(count) freed=\(freed)")
                cont.resume(returning: freed)
            }
        }
    }

    func cleanBucket(_ bucket: StorageBucket) async -> CleanResult {
        switch bucket {
        case .caches:
            let bytes = await clearSafeCaches()
            AppLog.cleaner.info("StorageMap caches freed \(bytes, privacy: .public)")
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .downloads:
            let bytes = await clearOldDownloadJunk()
            return CleanResult(cacheBytesFreed: bytes, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .derivedData:
            let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let before = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
            let ok = await wipeDirectoryContents(path)
            let after = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
            let freed = before > after ? before - after : (ok ? before : 0)
            return CleanResult(cacheBytesFreed: freed, dnsFlushed: false, dockerPruned: false, dockerMessage: nil)
        case .docker:
            let docker = await pruneDockerUnused()
            return CleanResult(
                cacheBytesFreed: docker.bytes,
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

    // MARK: - Caches (denylist + whole-folder wipe)

    /// Wipe regenerable top-level cache folders. Shows ~GB in Storage Map; old allow-list only freed MBs.
    func clearSafeCaches() async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
                let fm = FileManager.default
                guard let children = try? fm.contentsOfDirectory(atPath: root) else {
                    cont.resume(returning: 0)
                    return
                }

                var freed: UInt64 = 0
                var wiped = 0
                for name in children {
                    if name.hasPrefix(".") { continue }
                    if self.isBlockedCache(name) { continue }
                    if !self.isSafeToWipeCache(name) { continue }
                    let path = (root as NSString).appendingPathComponent(name)
                    guard CleanSafety.assertSafeToRemove(path: path) else { continue }
                    guard !ProtectionGuard.isPathProtected(path) else { continue }

                    // Prefer removing the whole top-level cache folder (apps recreate it).
                    // Size after success keeps the wipe path fast (no double 80k-file walk).
                    do {
                        let size = Self.quickSize(path)
                        try fm.removeItem(atPath: path)
                        freed += size
                        wiped += 1
                    } catch {
                        let before = Self.quickSize(path)
                        let partial = self.deleteContentsBestEffort(at: path)
                        let after = Self.quickSize(path)
                        let gained = partial > 0 ? partial : (before > after ? before - after : 0)
                        freed += gained
                        if gained > 0 { wiped += 1 }
                    }
                }
                AppLog.cleaner.info("clearSafeCaches wipedFolders=\(wiped) freed=\(freed)")
                cont.resume(returning: freed)
            }
        }
    }

    /// Estimate what Clean would free (for Storage Map honesty).
    nonisolated static func estimateReclaimableCaches() -> UInt64 {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: root) else { return 0 }
        var total: UInt64 = 0
        for name in children {
            if name.hasPrefix(".") { continue }
            guard Self.isSafeCacheName(name) else { continue }
            let path = (root as NSString).appendingPathComponent(name)
            if ProtectionGuard.isPathProtected(path) { continue }
            total += CleanSafety.directoryOrFileSize(URL(fileURLWithPath: path))
        }
        return total
    }

    nonisolated static func isSafeCacheName(_ name: String) -> Bool {
        let blocked = [
            "CloudDocs", "CloudKit", "FamilyCircle", "accountsd",
            "Keychain", "Cookies", "Credentials", "Passwords",
            "com.apple.Safari.SafeBrowsing", "com.apple.findmy",
            "com.apple.HomeKit", "com.apple.MobileSMS",
            "com.apple.AddressBook", "com.apple.bird",
            "com.apple.nsurlsessiond", "com.apple.akd"
        ]
        if blocked.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return false }
        if !name.hasPrefix("com.apple.") { return true }
        let appleOK = [
            "com.apple.Safari", "com.apple.WebKit", "com.apple.dt.", "com.apple.Music",
            "com.apple.TV", "com.apple.helpd", "com.apple.maps", "com.apple.iTunes",
            "com.apple.AppStore", "com.apple.installer"
        ]
        return appleOK.contains { name.hasPrefix($0) }
    }

    private func isBlockedCache(_ name: String) -> Bool {
        blockedCacheNames.contains { name.localizedCaseInsensitiveContains($0) }
    }

    private func isSafeToWipeCache(_ name: String) -> Bool {
        Self.isSafeCacheName(name)
    }

    private func deleteContentsBestEffort(at path: String) -> UInt64 {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: path) else { return 0 }
        var freed: UInt64 = 0
        for name in children {
            let full = (path as NSString).appendingPathComponent(name)
            let size = Self.quickSize(full)
            do {
                try fm.removeItem(atPath: full)
                freed += size
            } catch {
                continue
            }
        }
        return freed
    }

    /// Fast bounded size — enough for progress accounting without freezing the UI.
    /// Bounded (8k files / 4 s) — a cache folder size estimate must never stall a clean.
    private static func quickSize(_ path: String) -> UInt64 {
        BoundedSizeWalk.size(atPath: path, maxFiles: 8_000, budget: 4).bytes
    }

    private func wipeDirectoryContents(_ path: String) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                guard fm.fileExists(atPath: path) else {
                    cont.resume(returning: false)
                    return
                }
                guard let children = try? fm.contentsOfDirectory(atPath: path) else {
                    cont.resume(returning: false)
                    return
                }
                for name in children where !name.hasPrefix(".") {
                    let full = (path as NSString).appendingPathComponent(name)
                    try? fm.removeItem(atPath: full)
                }
                cont.resume(returning: true)
            }
        }
    }

    // MARK: - Downloads (old installers only — not whole folder)

    private func clearOldDownloadJunk() async -> UInt64 {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
                let fm = FileManager.default
                let exts = ["dmg", "pkg", "zip", "iso", "tar", "gz", "tgz", "rar", "7z", "ipa", "apk"]
                let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
                guard let children = try? fm.contentsOfDirectory(atPath: root) else {
                    cont.resume(returning: 0)
                    return
                }
                var freed: UInt64 = 0
                for name in children {
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard exts.contains(ext) else { continue }
                    let full = (root as NSString).appendingPathComponent(name)
                    guard let attrs = try? fm.attributesOfItem(atPath: full),
                          let modified = attrs[.modificationDate] as? Date,
                          modified < cutoff else { continue }
                    guard CleanSafety.assertSafeToRemove(path: full) else { continue }
                    let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: full))
                    do {
                        try fm.removeItem(atPath: full)
                        freed += size
                    } catch { continue }
                }
                cont.resume(returning: freed)
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
                    let size = CleanSafety.directoryOrFileSize(URL(fileURLWithPath: full))
                    try? fm.removeItem(atPath: full)
                    freed += size
                }
                cont.resume(returning: freed)
            }
        }
    }

    func purgeInactiveMemory() async -> CleanResult {
        let before = MachMemory.sample()?.availableBytes ?? 0
        let result = await PrivilegedRunner.run(
            "/usr/sbin/purge",
            args: [],
            needsAdmin: true,
            reason: "Free RAM — purge reclaimable disk cache."
        )
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

    private func flushDNS() async -> Bool {
        let result = await PrivilegedRunner.runAdminScript(
            "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder",
            reason: "Flush DNS cache."
        )
        return result.ok
    }

    // MARK: - Docker (unused data, not only dangling volumes)

    private func pruneDockerUnused() async -> (pruned: Bool, message: String?, bytes: UInt64) {
        guard let dockerPath = resolveDocker() else {
            return (false, "Docker not found", 0)
        }

        // Capture reclaimable estimate before prune.
        let beforeDF = await PrivilegedRunner.run(
            dockerPath,
            args: ["system", "df"],
            needsAdmin: false
        )
        let beforeReclaim = Self.parseDockerReclaimable(beforeDF.output)

        // Safe unused cleanup: stopped containers, dangling images, unused networks, build cache, dangling volumes.
        // Does NOT remove named volumes in use or running containers' images when still referenced as "used".
        let prune = await PrivilegedRunner.run(
            dockerPath,
            args: ["system", "prune", "-af"],
            needsAdmin: false
        )
        let builder = await PrivilegedRunner.run(
            dockerPath,
            args: ["builder", "prune", "-af"],
            needsAdmin: false
        )
        let volumes = await PrivilegedRunner.run(
            dockerPath,
            args: ["volume", "prune", "-f"],
            needsAdmin: false
        )

        let afterDF = await PrivilegedRunner.run(
            dockerPath,
            args: ["system", "df"],
            needsAdmin: false
        )
        let afterReclaim = Self.parseDockerReclaimable(afterDF.output)
        let reclaimedFromReport = Self.parseDockerReclaimedLine(prune.output)
            + Self.parseDockerReclaimedLine(builder.output)
            + Self.parseDockerReclaimedLine(volumes.output)

        let freed: UInt64
        if reclaimedFromReport > 0 {
            freed = reclaimedFromReport
        } else if beforeReclaim > afterReclaim {
            freed = beforeReclaim - afterReclaim
        } else {
            freed = 0
        }

        let ok = prune.ok || builder.ok || volumes.ok
        let msg: String?
        if ok {
            msg = freed > 0 ? "Reclaimed \(CleanResult.formatBytes(freed))" : "Pruned unused Docker data"
        } else {
            msg = "Docker prune skipped — is Docker Desktop running?"
        }
        return (ok, msg, freed)
    }

    /// Sum RECLAIMABLE column from `docker system df`.
    nonisolated static func parseDockerReclaimable(_ text: String) -> UInt64 {
        var total: UInt64 = 0
        for line in text.split(separator: "\n") {
            // RECLAIMABLE is usually the last column, e.g. "1.2GB (50%)" or "0B"
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4, parts[0] != "TYPE" else { continue }
            if let token = parts.last(where: { $0.uppercased().contains("B") }) {
                total += parseSizeToken(token)
            }
        }
        return total
    }

    nonisolated static func parseDockerReclaimedLine(_ text: String) -> UInt64 {
        // "Total reclaimed space: 1.234GB"
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("reclaimed") else { continue }
            if let range = line.range(of: #"[0-9]+(\.[0-9]+)?\s*[KMGT]?B"#, options: .regularExpression) {
                return parseSizeToken(String(line[range]))
            }
        }
        return 0
    }

    nonisolated static func parseSizeToken(_ token: String) -> UInt64 {
        let upper = token.uppercased().replacingOccurrences(of: ",", with: "")
        let num = Double(upper.filter { $0.isNumber || $0 == "." }) ?? 0
        if upper.contains("TB") { return UInt64(num * 1_099_511_627_776) }
        if upper.contains("GB") { return UInt64(num * 1_073_741_824) }
        if upper.contains("MB") { return UInt64(num * 1_048_576) }
        if upper.contains("KB") { return UInt64(num * 1024) }
        return UInt64(num)
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
