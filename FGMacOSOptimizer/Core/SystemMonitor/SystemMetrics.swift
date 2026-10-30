import Foundation

struct SystemMetrics: Equatable, Sendable {
    /// 0...1 RAM fullness from availability view.
    var memoryUsedFraction: Double
    var memoryWiredBytes: UInt64
    var memoryActiveBytes: UInt64
    var memoryInactiveBytes: UInt64
    var memoryCompressedBytes: UInt64
    var memoryFreeBytes: UInt64
    var memoryTotalBytes: UInt64
    var swapUsedBytes: UInt64
    var cpuUsageFraction: Double
    var thermalLevel: ThermalLevel
    var diskUsedFraction: Double
    var diskTotalBytes: UInt64
    var diskAvailableBytes: UInt64
    var batteryPercent: Double
    var batteryHasBattery: Bool
    var batteryCharging: Bool
    var memoryPressure: MemoryPressureLevel
    var timestamp: Date

    static let zero = SystemMetrics(
        memoryUsedFraction: 0,
        memoryWiredBytes: 0,
        memoryActiveBytes: 0,
        memoryInactiveBytes: 0,
        memoryCompressedBytes: 0,
        memoryFreeBytes: 0,
        memoryTotalBytes: 0,
        swapUsedBytes: 0,
        cpuUsageFraction: 0,
        thermalLevel: .nominal,
        diskUsedFraction: 0,
        diskTotalBytes: 0,
        diskAvailableBytes: 0,
        batteryPercent: 1,
        batteryHasBattery: false,
        batteryCharging: false,
        memoryPressure: .normal,
        timestamp: .distantPast
    )

    var memoryAvailableBytes: UInt64 {
        memoryFreeBytes &+ memoryInactiveBytes
    }

    var memoryAppUsedBytes: UInt64 {
        memoryWiredBytes &+ memoryActiveBytes &+ memoryCompressedBytes
    }

    /// Swap above this is a warning sign (not critical on its own).
    static let swapPressureBytes: UInt64 = 2 * 1024 * 1024 * 1024

    var hasSwapPressure: Bool {
        swapUsedBytes > Self.swapPressureBytes
    }

    /// One urgent condition at a time, most actionable first: disk → memory → heat.
    var urgentCondition: UrgentCondition? {
        // `.zero` has disk 0 — never flag before the first real sample.
        guard timestamp > .distantPast else { return nil }
        if diskTotalBytes > 0 {
            let freeRatio = Double(diskAvailableBytes) / Double(diskTotalBytes)
            if freeRatio < 0.08 || diskAvailableBytes < 10 * 1_073_741_824 {
                return .disk(freeBytes: diskAvailableBytes)
            }
        }
        if memoryPressure == .critical { return .memory }
        if thermalLevel.rawValue >= ThermalLevel.serious.rawValue { return .thermal(thermalLevel) }
        return nil
    }

    var memoryPressureColorBand: MetricBand {
        if memoryPressure != .normal { return memoryPressure.band }
        let availableRatio = memoryTotalBytes == 0 ? 1 : Double(memoryAvailableBytes) / Double(memoryTotalBytes)
        if availableRatio >= 0.20 { return .good }
        if availableRatio >= 0.10 { return .warn }
        return .bad
    }

    var availableMemoryRatio: Double {
        memoryTotalBytes == 0 ? 1 : Double(memoryAvailableBytes) / Double(memoryTotalBytes)
    }

    var cpuColorBand: MetricBand { MetricBand.from(fraction: cpuUsageFraction) }

    var diskColorBand: MetricBand {
        let freeRatio = diskTotalBytes == 0 ? 1 : Double(diskAvailableBytes) / Double(diskTotalBytes)
        if freeRatio >= 0.15 { return .good }
        if freeRatio >= 0.08 { return .warn }
        return .bad
    }

    static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }
}

/// Shown as a one-tap banner at the top of the popover.
enum UrgentCondition: Equatable, Sendable {
    case disk(freeBytes: UInt64)
    case memory
    case thermal(ThermalLevel)
}

enum ThermalLevel: Int, Sendable, Equatable {
    case nominal = 0, fair = 1, serious = 2, critical = 3

    var fraction: Double {
        switch self {
        case .nominal: return 0.18
        case .fair: return 0.45
        case .serious: return 0.75
        case .critical: return 1.0
        }
    }

    var title: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }

    var band: MetricBand {
        switch self {
        case .nominal: return .good
        case .fair: return .warn
        case .serious, .critical: return .bad
        }
    }
}

enum MetricBand: Sendable {
    case good, warn, bad

    static func from(fraction: Double) -> MetricBand {
        if fraction < 0.60 { return .good }
        if fraction < 0.85 { return .warn }
        return .bad
    }
}
