import Foundation
import AppKit
import Combine

struct CleanupHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let title: String
    let category: String
    let bytes: UInt64
    let originalPath: String
    let trashPath: String?
    let disposal: String
    var restored: Bool

    var canRestore: Bool {
        guard !restored, disposal == CleanDisposal.trash.rawValue, let trashPath else { return false }
        return FileManager.default.fileExists(atPath: trashPath)
    }
}

struct CleanupHistoryBatch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let summary: String
    let freedBytes: UInt64
    var entries: [CleanupHistoryEntry]
}

/// Persists cleaner runs and supports Undo (restore from Trash when still present).
@MainActor
final class CleanupHistoryStore: ObservableObject {
    static let shared = CleanupHistoryStore()

    @Published private(set) var batches: [CleanupHistoryBatch] = []

    private let fileURL: URL
    private let maxBatches = 40

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FGMacOSOptimizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("cleanup-history.json")
        load()
    }

    func record(title: String, category: CleanCategory, result: CleanRunResult, moves: [CleanupMove]) {
        guard !moves.isEmpty || result.freedBytes > 0 || result.memoryPurged else { return }
        let entries = moves.map { move in
            CleanupHistoryEntry(
                id: UUID(),
                date: Date(),
                title: move.title,
                category: category.rawValue,
                bytes: move.bytes,
                originalPath: move.originalPath,
                trashPath: move.trashPath,
                disposal: move.disposal.rawValue,
                restored: false
            )
        }
        let batch = CleanupHistoryBatch(
            id: UUID(),
            date: Date(),
            summary: result.summary.isEmpty ? title : result.summary,
            freedBytes: result.freedBytes,
            entries: entries
        )
        batches.insert(batch, at: 0)
        if batches.count > maxBatches {
            batches = Array(batches.prefix(maxBatches))
        }
        save()
    }

    @discardableResult
    func restore(_ entry: CleanupHistoryEntry) -> String {
        guard let trashPath = entry.trashPath else { return "Nothing to restore (permanent delete)." }
        let trashURL = URL(fileURLWithPath: trashPath)
        guard FileManager.default.fileExists(atPath: trashPath) else {
            return "Item no longer in Trash — empty Trash or already restored."
        }
        let dest = URL(fileURLWithPath: entry.originalPath)
        let parent = dest.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                let stamped = parent.appendingPathComponent(
                    dest.deletingPathExtension().lastPathComponent + "-restored-\(Int(Date().timeIntervalSince1970))." + dest.pathExtension
                )
                try FileManager.default.moveItem(at: trashURL, to: stamped)
            } else {
                try FileManager.default.moveItem(at: trashURL, to: dest)
            }
            markRestored(entry.id)
            return "Restored"
        } catch {
            return "Restore failed: \(error.localizedDescription)"
        }
    }

    func revealInTrash(_ entry: CleanupHistoryEntry) {
        guard let trashPath = entry.trashPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: trashPath)])
    }

    func clearAll() {
        batches = []
        save()
    }

    private func markRestored(_ id: UUID) {
        for bi in batches.indices {
            if let ei = batches[bi].entries.firstIndex(where: { $0.id == id }) {
                batches[bi].entries[ei].restored = true
                save()
                return
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CleanupHistoryBatch].self, from: data) else {
            batches = []
            return
        }
        batches = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(batches) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct CleanupMove: Sendable {
    let title: String
    let originalPath: String
    let trashPath: String?
    let bytes: UInt64
    let disposal: CleanDisposal
}
