import Foundation
import Combine

final class MetricsSampler: ObservableObject {
    @Published private(set) var metrics: SystemMetrics = .zero

    private let queue = DispatchQueue(label: "com.fgmacos.optimizer.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 2.0

    /// Disk / battery change slowly — cache to cut IOKit + volume queries.
    private var cachedDisk: DiskMonitor.Snapshot?
    private var cachedBattery: BatteryMonitor.Snapshot = .none
    private var lastDiskSampleAt: Date = .distantPast
    private var lastBatterySampleAt: Date = .distantPast
    private let diskTTL: TimeInterval = 12
    private let batteryTTL: TimeInterval = 20

    private var lastPublished: SystemMetrics = .zero

    func start(interval: TimeInterval = 2.0) {
        self.interval = interval
        MemoryPressureMonitor.shared.start()
        queue.async { _ = MachCPU.sample() }
        restartTimer()
        sampleNow(forceSlowSensors: true)
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.sampleNow() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        MemoryPressureMonitor.shared.stop()
    }

    func setInterval(_ newInterval: TimeInterval) {
        guard abs(newInterval - interval) > 0.05 else { return }
        interval = newInterval
        restartTimer()
    }

    func kick() {
        queue.async { [weak self] in
            _ = MachCPU.sample()
            self?.sampleNow(forceSlowSensors: true)
            self?.queue.asyncAfter(deadline: .now() + 0.45) { self?.sampleNow() }
        }
    }

    private func restartTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets the system coalesce wakes → better idle efficiency.
        let leewayMs = max(120, Int(interval * 1000 * 0.12))
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(leewayMs))
        t.setEventHandler { [weak self] in self?.sampleNow() }
        timer = t
        t.resume()
    }

    private func sampleNow(forceSlowSensors: Bool = false) {
        let now = Date()
        let mem = MachMemory.sample()
        let cpu = MachCPU.sample()
        let thermal = ThermalMonitor.sample()

        if forceSlowSensors || now.timeIntervalSince(lastDiskSampleAt) >= diskTTL || cachedDisk == nil {
            cachedDisk = DiskMonitor.sample()
            lastDiskSampleAt = now
        }
        if forceSlowSensors || now.timeIntervalSince(lastBatterySampleAt) >= batteryTTL {
            cachedBattery = BatteryMonitor.sample()
            lastBatterySampleAt = now
        }

        let disk = cachedDisk
        let battery = cachedBattery

        let freeBytes: UInt64
        let totalBytes: UInt64
        let inactive: UInt64
        let swap: UInt64
        if let mem {
            freeBytes = mem.freeBytes &+ mem.speculativeBytes
            totalBytes = mem.totalBytes
            inactive = mem.inactiveBytes
            swap = mem.swapUsedBytes
        } else {
            freeBytes = 0
            totalBytes = ProcessInfo.processInfo.physicalMemory
            inactive = 0
            swap = 0
        }
        let available = freeBytes &+ inactive
        let availableRatio = totalBytes == 0 ? 1 : Double(available) / Double(totalBytes)
        let hasSwap = swap > 512 * 1024 * 1024
        let pressure = MemoryPressureMonitor.shared.combined(
            availableRatio: availableRatio,
            hasSwapPressure: hasSwap
        )

        let snapshot: SystemMetrics
        if let mem {
            snapshot = SystemMetrics(
                memoryUsedFraction: mem.usedFraction,
                memoryWiredBytes: mem.wiredBytes,
                memoryActiveBytes: mem.activeBytes,
                memoryInactiveBytes: mem.inactiveBytes,
                memoryCompressedBytes: mem.compressedBytes,
                memoryFreeBytes: freeBytes,
                memoryTotalBytes: mem.totalBytes,
                swapUsedBytes: mem.swapUsedBytes,
                cpuUsageFraction: cpu,
                thermalLevel: thermal,
                diskUsedFraction: disk?.usedFraction ?? 0,
                diskTotalBytes: disk?.totalBytes ?? 0,
                diskAvailableBytes: disk?.availableBytes ?? 0,
                batteryPercent: battery.percent,
                batteryHasBattery: battery.hasBattery,
                batteryCharging: battery.isCharging,
                memoryPressure: pressure,
                timestamp: now
            )
        } else {
            snapshot = SystemMetrics(
                memoryUsedFraction: 0,
                memoryWiredBytes: 0,
                memoryActiveBytes: 0,
                memoryInactiveBytes: 0,
                memoryCompressedBytes: 0,
                memoryFreeBytes: 0,
                memoryTotalBytes: totalBytes,
                swapUsedBytes: 0,
                cpuUsageFraction: cpu,
                thermalLevel: thermal,
                diskUsedFraction: disk?.usedFraction ?? 0,
                diskTotalBytes: disk?.totalBytes ?? 0,
                diskAvailableBytes: disk?.availableBytes ?? 0,
                batteryPercent: battery.percent,
                batteryHasBattery: battery.hasBattery,
                batteryCharging: battery.isCharging,
                memoryPressure: pressure,
                timestamp: now
            )
        }

        // Skip UI publish when nothing meaningful changed.
        if snapshot.visuallyEqual(to: lastPublished) {
            return
        }
        lastPublished = snapshot

        DispatchQueue.main.async { [weak self] in
            self?.metrics = snapshot
        }
    }
}
