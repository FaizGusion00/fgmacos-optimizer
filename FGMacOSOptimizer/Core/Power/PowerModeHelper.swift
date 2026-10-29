import Foundation
import IOKit.ps

enum PowerModeHelper {
    static var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static var isOnBattery: Bool {
        let snap = BatteryMonitor.sample()
        return snap.hasBattery && !snap.isACPower && !snap.isCharging
    }

    /// Best-effort Low Power Mode via pmset (admin). No-op when onlyOnBattery and on AC.
    @MainActor
    static func setLowPower(_ enabled: Bool, onlyOnBattery: Bool) async {
        if onlyOnBattery && !isOnBattery { return }
        let flag = enabled ? "1" : "0"
        // -b = battery source; -a = all when forcing off for Gaming.
        let args: [String]
        if onlyOnBattery {
            args = ["-b", "lowpowermode", flag]
        } else {
            args = ["-a", "lowpowermode", flag]
        }
        _ = await PrivilegedRunner.run(
            "/usr/bin/pmset",
            args: args,
            needsAdmin: true,
            reason: enabled ? "Enable Low Power Mode." : "Disable Low Power Mode."
        )
    }

    static var powerModeTitle: String {
        if isLowPowerModeEnabled { return "Low Power" }
        return isOnBattery ? "Battery" : "AC Power"
    }
}
