import Foundation
import Darwin

enum MachCPU {
    /// Previous tick snapshot for delta calculation.
    private static var previous: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private static let lock = NSLock()

    /// Returns CPU usage as a fraction 0...1 based on tick deltas.
    static func sample() -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let ticks = cpuTicks() else { return 0 }

        defer { previous = ticks }

        guard let prev = previous else { return 0 }

        let userDelta = ticks.user &- prev.user
        let systemDelta = ticks.system &- prev.system
        let idleDelta = ticks.idle &- prev.idle
        let niceDelta = ticks.nice &- prev.nice

        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return 0 }

        let busy = userDelta + systemDelta + niceDelta
        return min(1.0, Double(busy) / Double(total))
    }

    private static func cpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )

        guard kr == KERN_SUCCESS, let infoArray else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        let loadInfoCount = MemoryLayout<processor_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        for i in 0..<Int(cpuCount) {
            let base = i * loadInfoCount
            user += UInt64(UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)]))
            system += UInt64(UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)]))
            nice += UInt64(UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)]))
        }

        return (user, system, idle, nice)
    }
}
