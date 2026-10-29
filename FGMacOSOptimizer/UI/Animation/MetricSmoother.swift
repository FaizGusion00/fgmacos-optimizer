import Foundation
import Combine

/// Soft-lerps gauge values. Runs only while values are moving; auto-pauses when settled.
final class MetricSmoother: ObservableObject {
    @Published private(set) var display: SystemMetrics = .zero

    private var target: SystemMetrics = .zero
    private var timer: Timer?
    private let lock = NSLock()
    private let factor: Double = 0.48
    private var isRunning = false
    private var isAnimating = false

    func start() {
        guard !isRunning else {
            resumeIfNeeded()
            return
        }
        isRunning = true
        lock.lock(); let t = target; lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.display = t
            self?.resumeIfNeeded()
        }
    }

    func stop() {
        isRunning = false
        isAnimating = false
        timer?.invalidate()
        timer = nil
    }

    func updateTarget(_ metrics: SystemMetrics) {
        lock.lock(); target = metrics; lock.unlock()
        if !isRunning {
            DispatchQueue.main.async { [weak self] in self?.display = metrics }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.resumeIfNeeded() }
    }

    func snap(to metrics: SystemMetrics) {
        lock.lock(); target = metrics; lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.display = metrics
            self?.pauseTimer()
        }
    }

    private func resumeIfNeeded() {
        guard isRunning else { return }
        lock.lock(); let t = target; lock.unlock()
        if display.visuallySettled(to: t) {
            pauseTimer()
            return
        }
        guard !isAnimating else { return }
        isAnimating = true
        timer?.invalidate()
        // 20 fps is plenty for gauges; 30 was burning main-thread for idle.
        let pulse = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(pulse, forMode: .common)
        timer = pulse
    }

    private func pauseTimer() {
        isAnimating = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning else { return }
        lock.lock(); let t = target; lock.unlock()
        let current = display

        if current.visuallySettled(to: t) {
            if current.timestamp != t.timestamp || current.thermalLevel != t.thermalLevel {
                display = t
            }
            pauseTimer()
            return
        }

        display = SystemMetrics(
            memoryUsedFraction: lerp(current.memoryUsedFraction, t.memoryUsedFraction),
            memoryWiredBytes: t.memoryWiredBytes,
            memoryActiveBytes: t.memoryActiveBytes,
            memoryInactiveBytes: t.memoryInactiveBytes,
            memoryCompressedBytes: t.memoryCompressedBytes,
            memoryFreeBytes: t.memoryFreeBytes,
            memoryTotalBytes: t.memoryTotalBytes,
            swapUsedBytes: t.swapUsedBytes,
            cpuUsageFraction: lerp(current.cpuUsageFraction, t.cpuUsageFraction),
            thermalLevel: t.thermalLevel,
            diskUsedFraction: lerp(current.diskUsedFraction, t.diskUsedFraction),
            diskTotalBytes: t.diskTotalBytes,
            diskAvailableBytes: t.diskAvailableBytes,
            batteryPercent: t.batteryPercent,
            batteryHasBattery: t.batteryHasBattery,
            batteryCharging: t.batteryCharging,
            memoryPressure: t.memoryPressure,
            timestamp: t.timestamp
        )
    }

    private func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * factor }
}

extension SystemMetrics {
    /// True when animated fields are close enough that further lerps are invisible.
    func visuallySettled(to other: SystemMetrics, epsilon: Double = 0.0015) -> Bool {
        abs(memoryUsedFraction - other.memoryUsedFraction) < epsilon &&
        abs(cpuUsageFraction - other.cpuUsageFraction) < epsilon &&
        abs(diskUsedFraction - other.diskUsedFraction) < epsilon &&
        thermalLevel == other.thermalLevel &&
        memoryPressure == other.memoryPressure &&
        abs(batteryPercent - other.batteryPercent) < 0.01 &&
        batteryCharging == other.batteryCharging
    }

    /// Equality for publish-skip (ignore high-frequency timestamps).
    func visuallyEqual(to other: SystemMetrics, epsilon: Double = 0.004) -> Bool {
        visuallySettled(to: other, epsilon: epsilon) &&
        memoryTotalBytes == other.memoryTotalBytes &&
        diskTotalBytes == other.diskTotalBytes &&
        bytesNear(memoryAvailableBytes, other.memoryAvailableBytes, tolerance: 8 * 1024 * 1024) &&
        bytesNear(diskAvailableBytes, other.diskAvailableBytes, tolerance: 64 * 1024 * 1024)
    }

    private func bytesNear(_ a: UInt64, _ b: UInt64, tolerance: UInt64) -> Bool {
        if a > b { return a &- b <= tolerance }
        return b &- a <= tolerance
    }
}
