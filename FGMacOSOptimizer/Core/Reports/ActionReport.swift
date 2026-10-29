import Foundation

/// Unified before/after toast for Turbo, Free RAM, Clean, Kill, Focus, etc.
struct ActionReport: Equatable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var availableBefore: UInt64
    var availableAfter: UInt64
    var bytesCleaned: UInt64
    var processesQuit: Int
    var dnsFlushed: Bool
    var focusName: String?
    var thermalBefore: ThermalLevel?
    var thermalAfter: ThermalLevel?
    var lowPowerChanged: Bool
    var detail: String?
    var createdAt: Date

    init(
        title: String,
        availableBefore: UInt64 = 0,
        availableAfter: UInt64 = 0,
        bytesCleaned: UInt64 = 0,
        processesQuit: Int = 0,
        dnsFlushed: Bool = false,
        focusName: String? = nil,
        thermalBefore: ThermalLevel? = nil,
        thermalAfter: ThermalLevel? = nil,
        lowPowerChanged: Bool = false,
        detail: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.availableBefore = availableBefore
        self.availableAfter = availableAfter
        self.bytesCleaned = bytesCleaned
        self.processesQuit = processesQuit
        self.dnsFlushed = dnsFlushed
        self.focusName = focusName
        self.thermalBefore = thermalBefore
        self.thermalAfter = thermalAfter
        self.lowPowerChanged = lowPowerChanged
        self.detail = detail
        self.createdAt = Date()
    }

    var summaryLine: String {
        var parts: [String] = []
        if availableBefore > 0 || availableAfter > 0 {
            let before = SystemMetrics.formatGB(availableBefore)
            let after = SystemMetrics.formatGB(availableAfter)
            if availableAfter != availableBefore {
                parts.append("RAM \(before)→\(after)")
            }
        }
        if processesQuit > 0 {
            parts.append("\(processesQuit) quit")
        }
        if bytesCleaned > 0 {
            parts.append("\(CleanResult.formatBytes(bytesCleaned)) cleaned")
        }
        if dnsFlushed { parts.append("DNS flushed") }
        if let focusName { parts.append(focusName) }
        if let tb = thermalBefore, let ta = thermalAfter, tb != ta {
            parts.append("Thermal \(tb.title)→\(ta.title)")
        }
        if lowPowerChanged { parts.append("Low Power updated") }
        if let detail, !detail.isEmpty, parts.isEmpty {
            parts.append(detail)
        }
        if parts.isEmpty {
            return detail ?? title
        }
        return parts.joined(separator: " · ")
    }

    static func fromCleanResult(_ result: CleanResult, title: String) -> ActionReport {
        ActionReport(
            title: title,
            availableBefore: result.availableBefore,
            availableAfter: result.availableAfter,
            bytesCleaned: result.cacheBytesFreed,
            processesQuit: 0,
            dnsFlushed: result.dnsFlushed,
            detail: result.summary
        )
    }
}

@MainActor
final class ActionReportStore: ObservableObject {
    static let shared = ActionReportStore()

    @Published private(set) var latest: ActionReport?
    private var clearTask: Task<Void, Never>?
    private let displaySeconds: TimeInterval = 3.2

    func publish(_ report: ActionReport) {
        clearTask?.cancel()
        latest = report
        clearTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(displaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if latest?.id == report.id {
                latest = nil
            }
        }
    }

    func clear() {
        clearTask?.cancel()
        latest = nil
    }
}
