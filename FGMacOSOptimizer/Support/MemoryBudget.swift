import Foundation

#if DEBUG
enum MemoryBudget {
    /// Soft budget for idle menu-bar mode. SwiftUI + AppKit typically land ~25–45 MB
    /// in Release after frameworks warm; Debug is higher. Flag only clear regressions.
    static let targetBytes: UInt64 = 45 * 1024 * 1024

    static func logIfOverBudget(tag: String = "idle") {
        let rss = residentBytes()
        if rss > targetBytes {
            print("[MemoryBudget] OVER \(tag): \(ByteCountFormatter.string(fromByteCount: Int64(rss), countStyle: .memory)) > 20 MB")
        } else {
            print("[MemoryBudget] OK \(tag): \(ByteCountFormatter.string(fromByteCount: Int64(rss), countStyle: .memory))")
        }
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
#endif
