import Foundation
import Combine

struct NetworkTalker: Equatable, Sendable {
    var name: String
    var bytesPerSec: UInt64
}

@MainActor
final class NetworkPulseMonitor: ObservableObject {
    @Published private(set) var uploadBytesPerSec: Double = 0
    @Published private(set) var downloadBytesPerSec: Double = 0
    @Published private(set) var topTalker: NetworkTalker?

    private var timer: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastSampleAt: Date?
    private var tickCount = 0

    func start(interval: TimeInterval = 2.0) {
        timer?.invalidate()
        sampleCounters(first: true)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func kick() { tick() }

    private func tick() {
        sampleCounters(first: false)
        tickCount += 1
        if tickCount % 4 == 0 {
            refreshTopTalker()
        }
    }

    private func sampleCounters(first: Bool) {
        // `netstat` spawn + parse off the main thread; publish on main.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let totals = Self.netstatTotals()
            Task { @MainActor in
                self?.applyCounters(totals, first: first)
            }
        }
    }

    private func applyCounters(_ totals: (UInt64, UInt64), first: Bool) {
        let (inn, out) = totals
        let now = Date()
        if let lastAt = lastSampleAt, !first {
            let dt = now.timeIntervalSince(lastAt)
            if dt > 0.2 {
                let din = inn >= lastBytesIn ? inn &- lastBytesIn : 0
                let dout = out >= lastBytesOut ? out &- lastBytesOut : 0
                downloadBytesPerSec = Double(din) / dt
                uploadBytesPerSec = Double(dout) / dt
            }
        }
        lastBytesIn = inn
        lastBytesOut = out
        lastSampleAt = now
    }

    private func refreshTopTalker() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let talker = Self.nettopTop()
            Task { @MainActor in
                self?.topTalker = talker
            }
        }
    }

    /// Sum Ibytes/Obytes from `netstat -ibn` (skip lo*). Runs on a utility queue.
    nonisolated private static func netstatTotals() -> (UInt64, UInt64) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-ibn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (0, 0)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 10 else { continue }
            let name = parts[0]
            if name.hasPrefix("lo") { continue }
            // Name Address ... Ipkts Ierrs Ibytes Opkts Oerrs Obytes
            // Columns vary; find numeric columns near end.
            guard let iBytes = UInt64(parts[6]), let oBytes = UInt64(parts[9]) else { continue }
            bytesIn += iBytes
            bytesOut += oBytes
        }
        return (bytesIn, bytesOut)
    }

    nonisolated private static func nettopTop() -> NetworkTalker? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-x"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(1.2)
        while process.isRunning, Date() < deadline {
            usleep(40_000)
        }
        if process.isRunning { process.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        var best: (String, UInt64)?
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            if name.lowercased().contains("nettop") || name == "time" { continue }
            let nums = parts.compactMap { UInt64($0) }
            let sum = nums.suffix(2).reduce(UInt64(0), &+)
            if sum == 0 { continue }
            if best == nil || sum > best!.1 {
                best = (name, sum)
            }
        }
        guard let best else { return nil }
        return NetworkTalker(name: best.0, bytesPerSec: best.1)
    }

    static func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
    }
}
