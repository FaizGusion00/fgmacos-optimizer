import Foundation

/// Snapshot for WidgetKit. Without a paid App Group signing identity we also
/// mirror to a shared temp file the widget can read (unsigned local builds).
enum SharedMetricsSnapshot {
    static let appGroupID = "group.com.fgmacos.optimizer"
    static let fileName = "metrics_snapshot.json"
    static let sharedTempURL = URL(fileURLWithPath: "/tmp/com.fgmacos.optimizer.metrics.json")

    struct Payload: Codable {
        var cpu: Double
        var ramAvailableGB: Double
        var ramUsedFraction: Double
        var turbo: Bool
        var thermal: Int
        var pressure: Int
        var updatedAt: Date
    }

    static var containerURL: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FGMacOSOptimizer", isDirectory: true)
    }

    static func write(from metrics: SystemMetrics, turbo: Bool) {
        let payload = Payload(
            cpu: metrics.cpuUsageFraction,
            ramAvailableGB: Double(metrics.memoryAvailableBytes) / 1_073_741_824.0,
            ramUsedFraction: metrics.memoryUsedFraction,
            turbo: turbo,
            thermal: metrics.thermalLevel.rawValue,
            pressure: metrics.memoryPressure.rawValue,
            updatedAt: Date()
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(payload) else { return }

        if let dir = containerURL {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        }
        try? data.write(to: sharedTempURL, options: .atomic)
    }

    static func read() -> Payload? {
        let candidates: [URL] = {
            var list: [URL] = [sharedTempURL]
            if let dir = containerURL {
                list.insert(dir.appendingPathComponent(fileName), at: 0)
            }
            return list
        }()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let payload = try? dec.decode(Payload.self, from: data) {
                return payload
            }
        }
        return nil
    }
}
