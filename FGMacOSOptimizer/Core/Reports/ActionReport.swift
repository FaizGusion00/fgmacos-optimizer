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
    var logsBytesFreed: UInt64
    var timeMachinePaused: Bool
    var spotlightExcluded: Int
    var memoryPurged: Bool

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
        detail: String? = nil,
        logsBytesFreed: UInt64 = 0,
        timeMachinePaused: Bool = false,
        spotlightExcluded: Int = 0,
        memoryPurged: Bool = false
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
        self.logsBytesFreed = logsBytesFreed
        self.timeMachinePaused = timeMachinePaused
        self.spotlightExcluded = spotlightExcluded
        self.memoryPurged = memoryPurged
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
        if logsBytesFreed > 0 {
            parts.append("logs \(CleanResult.formatBytes(logsBytesFreed))")
        }
        if memoryPurged, availableAfter <= availableBefore {
            parts.append("RAM purged")
        }
        if dnsFlushed { parts.append("DNS flushed") }
        if timeMachinePaused { parts.append("Time Machine paused") }
        if spotlightExcluded > 0 { parts.append("\(spotlightExcluded) folders kept out of Spotlight") }
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
            detail: result.summary,
            logsBytesFreed: result.logsBytesFreed,
            timeMachinePaused: result.timeMachineStopped,
            spotlightExcluded: result.spotlightExcluded,
            memoryPurged: result.memoryPurged
        )
    }
}

@MainActor
final class ActionReportStore: ObservableObject {
    static let shared = ActionReportStore()

    @Published private(set) var latest: ActionReport?
    private var clearTask: Task<Void, Never>?
    /// Minor actions fade; major ones (Quick Optimize, Deep Clean, Turbo…) stay until dismissed.
    static let transientSeconds: TimeInterval = 3.2

    func publish(_ report: ActionReport, autoClearAfter seconds: TimeInterval? = nil) {
        clearTask?.cancel()
        latest = report
        guard let seconds else { return }
        clearTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if latest?.id == report.id {
                latest = nil
            }
        }
    }

    func dismiss() {
        clearTask?.cancel()
        latest = nil
    }

    func clear() { dismiss() }
}
