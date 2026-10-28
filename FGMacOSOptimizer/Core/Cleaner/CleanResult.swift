import Foundation

struct CleanResult: Equatable, Sendable {
    var cacheBytesFreed: UInt64
    var dnsFlushed: Bool
    var dockerPruned: Bool
    var dockerMessage: String?
    var memoryPurged: Bool = false
    var availableBefore: UInt64 = 0
    var availableAfter: UInt64 = 0

    var summary: String {
        var parts: [String] = []
        if memoryPurged {
            let gained = availableAfter > availableBefore ? availableAfter - availableBefore : 0
            if gained > 0 {
                parts.append("RAM +\(Self.formatBytes(gained)) available")
            } else {
                parts.append("Disk cache purged")
            }
        }
        if cacheBytesFreed > 0 {
            parts.append("Caches \(Self.formatBytes(cacheBytesFreed))")
        } else if !memoryPurged {
            parts.append("Caches scanned")
        }
        if dnsFlushed { parts.append("DNS flushed") }
        if dockerPruned { parts.append("Docker volumes pruned") }
        else if let dockerMessage, !memoryPurged { parts.append(dockerMessage) }
        return parts.joined(separator: " · ")
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
