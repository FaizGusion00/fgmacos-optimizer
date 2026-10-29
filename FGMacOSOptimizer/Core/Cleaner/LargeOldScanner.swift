import Foundation

actor LargeOldScanner {
    private let minBytes: UInt64 = 100 * 1024 * 1024
    private let minAgeDays: Double = 30
    private let maxFiles = 50_000

    func scan() async -> [CleanItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let home = NSHomeDirectory()
                let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music"]
                    .map { (home as NSString).appendingPathComponent($0) }
                let fm = FileManager.default
                let cutoff = Date().addingTimeInterval(-self.minAgeDays * 24 * 3600)
                var found: [CleanItem] = []
                var seen = 0

                for root in roots {
                    guard let enumerator = fm.enumerator(
                        at: URL(fileURLWithPath: root),
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }

                    while let url = enumerator.nextObject() as? URL {
                        seen += 1
                        if seen > self.maxFiles { break }
                        guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                              vals.isRegularFile == true,
                              let size = vals.fileSize else { continue }
                        let bytes = UInt64(size)
                        let modified = vals.contentModificationDate ?? .distantFuture
                        let large = bytes >= self.minBytes
                        let old = modified < cutoff
                        guard large || (old && bytes >= 10 * 1024 * 1024) else { continue }
                        guard CleanSafety.assertSafeToRemove(path: url.path) else { continue }

                        var reasons: [String] = []
                        if large { reasons.append(">100 MB") }
                        if old { reasons.append(">30 days") }
                        found.append(CleanItem(
                            id: "large.\(url.path)",
                            category: .largeOld,
                            title: url.lastPathComponent,
                            subtitle: "\(reasons.joined(separator: " · ")) · \(url.deletingLastPathComponent().path)",
                            bytes: bytes,
                            paths: [url.path],
                            risk: .review,
                            disposal: .trash,
                            selected: false
                        ))
                    }
                }

                cont.resume(returning: found.sorted { $0.bytes > $1.bytes }.prefix(200).map { $0 })
            }
        }
    }
}
