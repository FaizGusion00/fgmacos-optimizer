import Foundation
import Combine

enum ThermalMonitor {
    static func sample() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}

/// Pushes thermal changes immediately (Apple posts this when state flips).
final class ThermalStateObserver {
    private var token: NSObjectProtocol?

    func start(onChange: @escaping (ThermalLevel) -> Void) {
        stop()
        token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange(ThermalMonitor.sample())
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}
