import Foundation
import IOKit.ps

enum BatteryMonitor {
    struct Snapshot: Sendable, Equatable {
        var hasBattery: Bool
        var percent: Double // 0...1
        var isCharging: Bool
        var isACPower: Bool

        static let none = Snapshot(hasBattery: false, percent: 1, isCharging: false, isACPower: true)
    }

    static func sample() -> Snapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return .none
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = Swift.max(desc[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let power = desc[kIOPSPowerSourceStateKey] as? String
            let ac = power == kIOPSACPowerValue

            return Snapshot(
                hasBattery: true,
                percent: Swift.min(1, Swift.max(0, Double(capacity) / Double(maxCap))),
                isCharging: charging,
                isACPower: ac
            )
        }
        return .none
    }
}
