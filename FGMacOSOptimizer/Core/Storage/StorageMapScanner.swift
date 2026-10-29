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

    var needsConfirm: Bool {
        switch self {
        case .caches: return false
        case .downloads, .derivedData, .docker, .trash: return true
        }
    }
}

struct StorageBucketSize: Identifiable, Equatable, Sendable {
    var id: String { bucket.rawValue }
    var bucket: StorageBucket
    var bytes: UInt64
    var detail: String
    var isScanning: Bool
}

actor StorageMapScanner {
    private(set) var lastSizes: [StorageBucket: StorageBucketSize] = [:]

    func refreshAll() async -> [StorageBucketSize] {
        var results: [StorageBucketSize] = []
        for bucket in StorageBucket.allCases {
            let size = await measure(bucket)
            lastSizes[bucket] = size
            results.append(size)
        }
        return results.sorted { $0.bucket.rawValue < $1.bucket.rawValue }
    }

    func measure(_ bucket: StorageBucket) async -> StorageBucketSize {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let home = NSHomeDirectory()
                switch bucket {
                case .caches:
                    let path = (home as NSString).appendingPathComponent("Library/Caches")
                    let bytes = Self.directorySize(path, maxDepth: 3)
                    cont.resume(returning: StorageBucketSize(
                        bucket: .caches, bytes: bytes, detail: "~/Library/Caches", isScanning: false
                    ))
                case .downloads:
                    let path = (home as NSString).appendingPathComponent("Downloads")
                    let bytes = Self.directorySize(path, maxDepth: 4)
                    cont.resume(returning: StorageBucketSize(
                        bucket: .downloads, bytes: bytes, detail: "~/Downloads", isScanning: false
                    ))
                case .derivedData:
                    let path = (home as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData")
                    let bytes = Self.directorySize(path, maxDepth: 3)
                    cont.resume(returning: StorageBucketSize(
                        bucket: .derivedData, bytes: bytes, detail: "Xcode build cache", isScanning: false
                    ))
                case .docker:
                    let docker = Self.resolveDocker()
                    guard let docker else {
                        cont.resume(returning: StorageBucketSize(
                            bucket: .docker, bytes: 0, detail: "Docker not found", isScanning: false
                        ))
                        return
                    }
                    let out = Self.run(docker, args: ["system", "df", "--format", "{{.Size}}"])
                    cont.resume(returning: StorageBucketSize(
                        bucket: .docker,
                        bytes: Self.parseDockerSize(out),
                        detail: out.isEmpty ? "docker system df" : out.prefix(80).description,
                        isScanning: false
                    ))
                case .trash:
                    let path = (home as NSString).appendingPathComponent(".Trash")
                    let bytes = Self.directorySize(path, maxDepth: 4)
                    cont.resume(returning: StorageBucketSize(
                        bucket: .trash, bytes: bytes, detail: "~/.Trash", isScanning: false
                    ))
                }
            }
        }
    }

    private static func directorySize(_ path: String, maxDepth: Int) -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return 0 }
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: UInt64 = 0
        var count = 0
        let maxFiles = 40_000
        while let item = enumerator.nextObject() as? URL {
            if enumerator.level > maxDepth { enumerator.skipDescendants(); continue }
            count += 1
            if count > maxFiles { break }
            guard let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
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

    private static func parseDockerSize(_ text: String) -> UInt64 {
        // Rough parse of first size token like "12.3GB"
        let token = text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).first.map(String.init) ?? ""
        let upper = token.uppercased()
        let num = Double(upper.filter { $0.isNumber || $0 == "." }) ?? 0
        if upper.contains("GB") { return UInt64(num * 1_073_741_824) }
        if upper.contains("MB") { return UInt64(num * 1_048_576) }
        if upper.contains("KB") { return UInt64(num * 1024) }
        return 0
    }
}
