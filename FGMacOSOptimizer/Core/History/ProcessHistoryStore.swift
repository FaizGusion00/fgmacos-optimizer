import Foundation
import Combine

struct ProcessHistorySample: Codable, Equatable, Sendable {
    var name: String
    var bundleID: String?
    var cpuPercent: Double
    var at: Date
}

struct HallOfFameEntry: Identifiable, Equatable, Sendable {
    var id: String { key }
    var key: String
    var name: String
    var bundleID: String?
    var score: Double
    var samples: Int
}

@MainActor
final class ProcessHistoryStore: ObservableObject {
    @Published private(set) var hallOfFame: [HallOfFameEntry] = []

    private var samples: [ProcessHistorySample] = []
    private let maxSamples = 8_000
    private let fileURL: URL
    private let retention: TimeInterval = 24 * 60 * 60

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FGMacOSOptimizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("process_history.json")
        load()
        recompute()
    }

    func record(top: [TopProcess], paused: Bool) {
        guard !paused else { return }
        let now = Date()
        for p in top.prefix(8) {
            samples.append(ProcessHistorySample(
                name: p.name,
                bundleID: nil,
                cpuPercent: p.cpuPercent,
                at: now
            ))
        }
        prune()
        if samples.count % 40 == 0 {
            persist()
            recompute()
        }
    }

    func clear() {
        samples.removeAll()
        persist()
        recompute()
    }

    func recompute() {
        prune()
        var agg: [String: (name: String, bid: String?, score: Double, n: Int)] = [:]
        for s in samples {
            let key = s.bundleID ?? s.name
            var cur = agg[key] ?? (s.name, s.bundleID, 0, 0)
            cur.score += s.cpuPercent
            cur.n += 1
            agg[key] = cur
        }
        hallOfFame = agg.map {
            HallOfFameEntry(key: $0.key, name: $0.value.name, bundleID: $0.value.bid, score: $0.value.score, samples: $0.value.n)
        }
        .sorted { $0.score > $1.score }
        .prefix(8)
        .map { $0 }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        samples.removeAll { $0.at < cutoff }
        if samples.count > maxSamples {
            samples = Array(samples.suffix(maxSamples))
        }
    }

    private func persist() {
        prune()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        samples = (try? dec.decode([ProcessHistorySample].self, from: data)) ?? []
        prune()
    }
}
