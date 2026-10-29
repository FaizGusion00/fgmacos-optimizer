import Foundation

enum StorageBucket: String, CaseIterable, Identifiable, Sendable {
    case caches
    case downloads
    case derivedData
    case docker
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: return "Caches"
        case .downloads: return "Downloads"
        case .derivedData: return "Xcode DerivedData"
        case .docker: return "Docker"
        case .trash: return "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .caches: return "internaldrive"
        case .downloads: return "arrow.down.circle"
        case .derivedData: return "hammer"
        case .docker: return "shippingbox"
        case .trash: return "trash"
        }
    }

    var needsConfirm: Bool { true }

    var confirmMessage: String {
        switch self {
        case .caches:
            return "Deletes regenerable app caches under ~/Library/Caches (Chrome, Docker app cache, VS Code, Homebrew, etc.). Skips CloudKit/Keychain and other sensitive folders. Apps recreate caches as needed."
        case .downloads:
            return "Removes old installers in ~/Downloads (.dmg/.pkg/.zip older than 7 days) only — not your documents."
        case .derivedData:
            return "Wipes Xcode DerivedData build cache. Next Xcode build will be slower once."
        case .docker:
            return "Runs docker system prune -af + builder prune + volume prune. Removes unused images, containers, build cache, and dangling volumes. Running containers stay up; unused images go away."
        case .trash:
            return "Permanently empties ~/.Trash."
        }
    }
}

struct StorageBucketSize: Identifiable, Equatable, Sendable {
    var id: String { bucket.rawValue }
    var bucket: StorageBucket
    var bytes: UInt64
    var reclaimableBytes: UInt64
    var detail: String
    var isScanning: Bool
}

actor StorageMapScanner {
    private(set) var lastSizes: [StorageBucket: StorageBucketSize] = [:]

    func refreshAll() async -> [StorageBucketSize] {
        // Parallel light measures — avoid serial multi-GB walks blocking the UI.
        async let caches = measureCaches()
        async let downloads = measurePath(
            bucket: .downloads,
            path: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"),
            detail: "~/Downloads · old .dmg/.pkg/.zip (7d+)",
            reclaimSameAsTotal: true
        )
        async let derived = measurePath(
            bucket: .derivedData,
            path: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            detail: "Xcode build cache",
            reclaimSameAsTotal: true
        )
        async let docker = measureDocker()
        async let trash = measurePath(
            bucket: .trash,
            path: (NSHomeDirectory() as NSString).appendingPathComponent(".Trash"),
            detail: "~/.Trash",
            reclaimSameAsTotal: true
        )
        let results = await [caches, downloads, derived, docker, trash]
        for item in results { lastSizes[item.bucket] = item }
        return results.sorted { $0.bucket.rawValue < $1.bucket.rawValue }
    }

    private func measureCaches() async -> StorageBucketSize {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let root = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches")
                let sized = Self.sizedCacheBuckets(root: root)
                cont.resume(returning: StorageBucketSize(
                    bucket: .caches,
                    bytes: sized.total,
                    reclaimableBytes: sized.reclaimable,
                    detail: sized.reclaimable > 0
                        ? "~/Library/Caches · \(CleanResult.formatBytes(sized.reclaimable)) safe to clean"
                        : "~/Library/Caches",
                    isScanning: false
                ))
            }
        }
    }

    private func measurePath(
        bucket: StorageBucket,
        path: String,
        detail: String,
        reclaimSameAsTotal: Bool
    ) async -> StorageBucketSize {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let bytes = Self.fastDirectorySize(path, maxFiles: 25_000)
                cont.resume(returning: StorageBucketSize(
                    bucket: bucket,
                    bytes: bytes,
                    reclaimableBytes: reclaimSameAsTotal ? bytes : 0,
                    detail: detail,
                    isScanning: false
                ))
            }
        }
    }

    private func measureDocker() async -> StorageBucketSize {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let docker = Self.resolveDocker() else {
                    cont.resume(returning: StorageBucketSize(
                        bucket: .docker, bytes: 0, reclaimableBytes: 0,
                        detail: "Docker not found", isScanning: false
                    ))
                    return
                }
                let out = Self.run(docker, args: ["system", "df"])
                let total = Self.parseDockerTotal(out)
                let reclaim = SystemCleaner.parseDockerReclaimable(out)
                cont.resume(returning: StorageBucketSize(
                    bucket: .docker,
                    bytes: max(total, reclaim),
                    reclaimableBytes: reclaim,
                    detail: reclaim > 0
                        ? "\(CleanResult.formatBytes(reclaim)) reclaimable (unused)"
                        : (out.isEmpty ? "docker system df" : String(out.prefix(60))),
                    isScanning: false
                ))
            }
        }
    }

    /// One pass: total + reclaimable for ~/Library/Caches (no double walk).
    private static func sizedCacheBuckets(root: String) -> (total: UInt64, reclaimable: UInt64) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: root) else { return (0, 0) }
        var total: UInt64 = 0
        var reclaimable: UInt64 = 0
        for name in children {
            if name.hasPrefix(".") { continue }
            let path = (root as NSString).appendingPathComponent(name)
            let size = fastDirectorySize(path, maxFiles: 12_000)
            total += size
            if SystemCleaner.isSafeCacheName(name), !ProtectionGuard.isPathProtected(path) {
                reclaimable += size
            }
        }
        return (total, reclaimable)
    }

    /// Bounded size walk — keeps Storage Map snappy on large trees.
    private static func fastDirectorySize(_ path: String, maxFiles: Int) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: UInt64 = 0
        var n = 0
        while let item = enumerator.nextObject() as? URL {
            n += 1
            if n > maxFiles { break }
            guard let vals = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let size = vals.fileSize else { continue }
            total += UInt64(size)
        }
        return total
    }

    private static func resolveDocker() -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ path: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseDockerTotal(_ text: String) -> UInt64 {
        var total: UInt64 = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4, parts[0] != "TYPE" else { continue }
            if parts.count > 3 {
                total += SystemCleaner.parseSizeToken(parts[3])
            }
        }
        return total
    }
}
