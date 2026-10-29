import Foundation
import CryptoKit

actor DuplicateScanner {
    private var cancelled = false

    func cancel() { cancelled = true }

    func scan(root: String? = nil) async -> [CleanItem] {
        cancelled = false
        let base = root ?? (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: base),
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    cont.resume(returning: [])
                    return
                }

                var bySize: [UInt64: [URL]] = [:]
                var n = 0
                while let url = enumerator.nextObject() as? URL {
                    if self.cancelled { break }
                    n += 1
                    if n > 30_000 { break }
                    guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          vals.isRegularFile == true,
                          let size = vals.fileSize, size >= 64 * 1024 else { continue }
                    bySize[UInt64(size), default: []].append(url)
                }

                var items: [CleanItem] = []
                for (size, urls) in bySize where urls.count > 1 {
                    if self.cancelled { break }
                    var byHash: [String: [URL]] = [:]
                    for url in urls {
                        if let h = Self.sampleHash(url) {
                            byHash[h, default: []].append(url)
                        }
                    }
                    for (hash, group) in byHash where group.count > 1 {
                        // Keep newest as original; select older for trash.
                        let sorted = group.sorted { a, b in
                            let ma = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                            let mb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                            return ma > mb
                        }
                        let keep = sorted[0]
                        for dup in sorted.dropFirst() {
                            guard CleanSafety.assertSafeToRemove(path: dup.path) else { continue }
                            items.append(CleanItem(
                                id: "dup.\(hash).\(dup.path)",
                                category: .duplicates,
                                title: dup.lastPathComponent,
                                subtitle: "Duplicate of \(keep.lastPathComponent) · \(CleanSafety.formatBytes(size))",
                                bytes: size,
                                paths: [dup.path],
                                risk: .review,
                                disposal: .trash,
                                selected: false,
                                meta: ["keep": keep.path, "hash": hash]
                            ))
                        }
                    }
                }
                cont.resume(returning: items.sorted { $0.bytes > $1.bytes })
            }
        }
    }

    private static func sampleHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data1 = try? handle.read(upToCount: 1_048_576) ?? Data()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var data2 = Data()
        if size > 2_097_152 {
            try? handle.seek(toOffset: UInt64(size - 1_048_576))
            data2 = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        }
        var hasher = SHA256()
        if let data1 { hasher.update(data: data1) }
        hasher.update(data: data2)
        hasher.update(data: withUnsafeBytes(of: size) { Data($0) })
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
