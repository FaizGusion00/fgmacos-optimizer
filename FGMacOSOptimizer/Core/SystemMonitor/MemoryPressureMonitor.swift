import Foundation
import Dispatch

enum MemoryPressureLevel: Int, Sendable, Equatable, Comparable {
    case normal = 0
    case warning = 1
    case critical = 2

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }

    var band: MetricBand {
        switch self {
        case .normal: return .good
        case .warning: return .warn
        case .critical: return .bad
        }
    }

    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Tracks OS memory-pressure notifications and merges with heuristic fallback.
final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()

    private let lock = NSLock()
    private var _level: MemoryPressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?

    var level: MemoryPressureLevel {
        lock.lock()
        defer { lock.unlock() }
        return _level
    }

    func start() {
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let raw = src.data
            let next: MemoryPressureLevel
            if raw.contains(.critical) {
                next = .critical
            } else if raw.contains(.warning) {
                next = .warning
            } else {
                next = .normal
            }
            self.lock.lock()
            self._level = next
            self.lock.unlock()
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Combine DispatchSource level with swap/available heuristics.
    func combined(availableRatio: Double, hasSwapPressure: Bool) -> MemoryPressureLevel {
        var level = self.level
        if availableRatio < 0.08 || hasSwapPressure {
            level = max(level, .critical)
        } else if availableRatio < 0.15 {
            level = max(level, .warning)
        }
        return level
    }
}
