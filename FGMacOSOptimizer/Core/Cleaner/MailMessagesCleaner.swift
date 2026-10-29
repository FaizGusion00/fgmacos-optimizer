import Foundation

actor MailMessagesCleaner {
    private let minBytes: UInt64 = 50 * 1024 * 1024
    private let minAgeDays: Double = 90

    func scan() async -> [CleanItem] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [CleanItem] = []
                let home = NSHomeDirectory()
                let cutoff = Date().addingTimeInterval(-self.minAgeDays * 24 * 3600)

                let roots: [(String, String)] = [
                    ("Mail Downloads", (home as NSString).appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")),
                    ("Mail Attachments", (home as NSString).appendingPathComponent("Library/Mail Downloads")),
                    ("Messages Attachments", (home as NSString).appendingPathComponent("Library/Messages/Attachments"))
                ]

                let fm = FileManager.default
                for (label, root) in roots {
                    guard fm.fileExists(atPath: root) else { continue }
                    guard let enumerator = fm.enumerator(
                        at: URL(fileURLWithPath: root),
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    var n = 0
                    while let url = enumerator.nextObject() as? URL {
                        n += 1
                        if n > 40_000 { break }
                        guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                              vals.isRegularFile == true,
                              let size = vals.fileSize else { continue }
                        let bytes = UInt64(size)
                        let modified = vals.contentModificationDate ?? .distantFuture
                        guard bytes >= self.minBytes, modified < cutoff else { continue }
                        guard CleanSafety.assertSafeToRemove(path: url.path) else { continue }
                        items.append(CleanItem(
                            id: "mail.\(url.path)",
                            category: .mailMessages,
                            title: url.lastPathComponent,
                            subtitle: "\(label) · >50MB · >90d",
                            bytes: bytes,
                            paths: [url.path],
                            risk: .review,
                            disposal: .trash,
                            selected: false
                        ))
                    }
                }
                cont.resume(returning: items.sorted { $0.bytes > $1.bytes }.prefix(100).map { $0 })
            }
        }
    }
}
