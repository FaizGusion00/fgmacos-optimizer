import Foundation
import Darwin
import AppKit

enum ProcessCPUSampler {
    struct Sample: Sendable {
        let pid: Int32
        let name: String
        let cpuPercent: Double
    }

    enum Mode: Sendable {
        /// All processes (popover open / deep scan).
        case full
        /// User apps + previously hot PIDs only (background).
        case lite
    }

    /// Rough per-process CPU% using `proc_pidinfo` + previous totals.
    private static var previousCPU: [Int32: Double] = [:]
    private static var previousTime: Date = .distantPast
    private static var nameCache: [Int32: String] = [:]
    private static var hotPIDs: Set<Int32> = []
    private static let lock = NSLock()

    static func topConsumers(limit: Int = 15, mode: Mode = .full) -> [Sample] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let elapsed = max(0.15, now.timeIntervalSince(previousTime))
        previousTime = now

        var results: [Sample] = []
        let pids = candidatePIDs(mode: mode)

        var nextTotals: [Int32: Double] = [:]
        var nextHot: Set<Int32> = []

        for pid in pids {
            guard let usage = cpuTime(for: pid) else { continue }
            nextTotals[pid] = usage

            let prev = previousCPU[pid] ?? usage
            let delta = max(0, usage - prev)
            // usage is in seconds of CPU time; convert to % of one core, capped.
            let percent = min(400.0, (delta / elapsed) * 100.0)
            if percent >= 1.5 {
                guard let name = cachedName(for: pid) else { continue }
                results.append(Sample(pid: pid, name: name, cpuPercent: percent))
                if percent >= 40 { nextHot.insert(pid) }
            }
        }

        // Keep previous totals for PIDs we skipped in lite mode so deltas stay sane.
        if mode == .lite {
            for (pid, total) in previousCPU where nextTotals[pid] == nil {
                nextTotals[pid] = total
            }
        }

        previousCPU = nextTotals
        hotPIDs = nextHot.union(results.filter { $0.cpuPercent >= 55 }.map(\.pid))
        // Bound growth
        if previousCPU.count > 400 {
            previousCPU = Dictionary(uniqueKeysWithValues: previousCPU.suffix(200))
        }
        if nameCache.count > 500 {
            nameCache = Dictionary(uniqueKeysWithValues: nameCache.suffix(200))
        }

        return results.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit).map { $0 }
    }

    private static func candidatePIDs(mode: Mode) -> [Int32] {
        switch mode {
        case .full:
            return runningPIDs()
        case .lite:
            var set = Set(hotPIDs)
            // MainActor-safe enough: NSWorkspace is OK from background for read of runningApplications.
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                set.insert(app.processIdentifier)
            }
            return Array(set)
        }
    }

    private static func runningPIDs() -> [Int32] {
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(count))
        let filled = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, Int32(MemoryLayout<pid_t>.size * Int(count)))
        }
        let n = Int(filled) / MemoryLayout<pid_t>.size
        return Array(buffer.prefix(n)).filter { $0 > 0 }
    }

    private static func cpuTime(for pid: Int32) -> Double? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
                proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, raw, size)
            }
        }
        guard result == size else { return nil }
        let user = Double(info.ptinfo.pti_total_user) / Double(NSEC_PER_SEC)
        let system = Double(info.ptinfo.pti_total_system) / Double(NSEC_PER_SEC)
        return user + system
    }

    private static func cachedName(for pid: Int32) -> String? {
        if let cached = nameCache[pid] { return cached }
        guard let name = processName(for: pid) else { return nil }
        nameCache[pid] = name
        return name
    }

    private static func processName(for pid: Int32) -> String? {
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = name.withUnsafeMutableBufferPointer { ptr in
            proc_name(pid, ptr.baseAddress, UInt32(MAXPATHLEN))
        }
        guard result > 0 else { return nil }
        return String(cString: name)
    }
}
