import Foundation

enum DiskMonitor {
    struct Snapshot: Sendable {
        var totalBytes: UInt64
        var freeBytes: UInt64
        var availableBytes: UInt64 // important for APFS (purgeable-aware)

        var usedBytes: UInt64 {
            totalBytes > availableBytes ? totalBytes - availableBytes : 0
        }

        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return min(1, Double(usedBytes) / Double(totalBytes))
        }

        var band: MetricBand {
            let freeRatio = totalBytes == 0 ? 1 : Double(availableBytes) / Double(totalBytes)
            if freeRatio >= 0.15 { return .good }
            if freeRatio >= 0.08 { return .warn }
            return .bad
        }
    }

    static func sample(path: String = "/") -> Snapshot? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacity ?? 0)
        let important: UInt64
        if let v = values.volumeAvailableCapacityForImportantUsage {
            important = UInt64(v)
        } else {
            important = free
        }
        guard total > 0 else { return nil }
        return Snapshot(totalBytes: total, freeBytes: free, availableBytes: important)
    }
}
