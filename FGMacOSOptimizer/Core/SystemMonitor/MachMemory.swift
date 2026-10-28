import Foundation
import Darwin

enum MachMemory {
    struct Snapshot: Sendable {
        var wiredBytes: UInt64
        var activeBytes: UInt64
        var inactiveBytes: UInt64
        var compressedBytes: UInt64
        var freeBytes: UInt64
        var speculativeBytes: UInt64
        var totalBytes: UInt64
        var swapUsedBytes: UInt64

        /// Reclaimable quickly (file cache / inactive / free).
        var availableBytes: UInt64 {
            freeBytes &+ inactiveBytes &+ speculativeBytes
        }

        /// Wired + active + compressed — Activity Monitor-style “Memory Used”.
        var appUsedBytes: UInt64 {
            wiredBytes &+ activeBytes &+ compressedBytes
        }

        /// Gauge value: fraction of RAM that is NOT available (honest, no fake bump).
        /// Matches “2.9 GB free of 16 GB” → ~82% in use of capacity from availability view.
        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            let used = Double(totalBytes &- min(totalBytes, availableBytes))
            return min(1, max(0, used / Double(totalBytes)))
        }

        var swapPressure: Bool {
            swapUsedBytes > 512 * 1024 * 1024
        }
    }

    static func sample() -> Snapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        return Snapshot(
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            activeBytes: UInt64(stats.active_count) * pageSize,
            inactiveBytes: UInt64(stats.inactive_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            freeBytes: UInt64(stats.free_count) * pageSize,
            speculativeBytes: UInt64(stats.speculative_count) * pageSize,
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            swapUsedBytes: swapUsageBytes()
        )
    }

    private static func swapUsageBytes() -> UInt64 {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 else { return 0 }
        return UInt64(xsw.xsu_used)
    }
}
