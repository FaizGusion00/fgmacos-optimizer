import Foundation

enum CleanCategory: String, CaseIterable, Identifiable, Sendable {
    case smartCare
    case uninstaller
    case largeOld
    case duplicates
    case loginItems
    case snapshots
    case dev
    case mailMessages
    case spaceLens
    case browser
    case schedule
    case protection
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: return "Smart Care"
        case .uninstaller: return "Uninstaller"
        case .largeOld: return "Large & Old"
        case .duplicates: return "Duplicates"
        case .loginItems: return "Startup"
        case .snapshots: return "Snapshots"
        case .dev: return "Dev"
        case .mailMessages: return "Mail & Messages"
        case .spaceLens: return "Space Lens"
        case .browser: return "Browsers"
        case .schedule: return "Schedule"
        case .protection: return "Protection"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: return "sparkles"
        case .uninstaller: return "app.badge.checkmark"
        case .largeOld: return "doc.badge.ellipsis"
        case .duplicates: return "doc.on.doc"
        case .loginItems: return "bolt.horizontal.circle"
        case .snapshots: return "clock.arrow.circlepath"
        case .dev: return "hammer"
        case .mailMessages: return "envelope"
        case .spaceLens: return "chart.pie"
        case .browser: return "globe"
        case .schedule: return "calendar"
        case .protection: return "hand.raised.fill"
        case .history: return "arrow.uturn.backward.circle"
        }
    }
}

enum CleanRisk: String, Sendable {
    case safeJunk
    case review
    case destructive

    var defaultSelected: Bool {
        switch self {
        case .safeJunk: return true
        case .review, .destructive: return false
        }
    }
}

enum CleanDisposal: String, Sendable {
    case trash
    case delete
}

struct CleanItem: Identifiable, Equatable, Sendable {
    let id: String
    var category: CleanCategory
    var title: String
    var subtitle: String
    var bytes: UInt64
    var paths: [String]
    var risk: CleanRisk
    var disposal: CleanDisposal
    var selected: Bool
    var meta: [String: String]

    init(
        id: String = UUID().uuidString,
        category: CleanCategory,
        title: String,
        subtitle: String = "",
        bytes: UInt64,
        paths: [String],
        risk: CleanRisk = .review,
        disposal: CleanDisposal = .trash,
        selected: Bool? = nil,
        meta: [String: String] = [:]
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.bytes = bytes
        self.paths = paths
        self.risk = risk
        self.disposal = disposal
        self.selected = selected ?? risk.defaultSelected
        self.meta = meta
    }
}

struct CleanRunResult: Equatable, Sendable {
    var freedBytes: UInt64 = 0
    var itemsProcessed: Int = 0
    var errors: [String] = []
    var memoryPurged: Bool = false
    var availableBefore: UInt64 = 0
    var availableAfter: UInt64 = 0

    var summary: String {
        var parts: [String] = []
        if freedBytes > 0 { parts.append("\(CleanSafety.formatBytes(freedBytes)) freed") }
        if itemsProcessed > 0 { parts.append("\(itemsProcessed) items") }
        if memoryPurged { parts.append("RAM purged") }
        if parts.isEmpty { return errors.first ?? "Nothing cleaned" }
        return parts.joined(separator: " · ")
    }
}

struct CleanApplyOutcome: Sendable {
    var result = CleanRunResult()
    var moves: [CleanupMove] = []
}

enum CleanExecutor {
    static func apply(_ items: [CleanItem]) -> CleanApplyOutcome {
        var outcome = CleanApplyOutcome()
        for item in items where item.selected {
            for path in item.paths {
                guard CleanSafety.assertSafeToRemove(path: path) else {
                    outcome.result.errors.append("Blocked: \(path)")
                    continue
                }
                let url = URL(fileURLWithPath: path)
                switch item.disposal {
                case .trash:
                    let trash = CleanSafety.trash(url)
                    if trash.ok {
                        outcome.result.freedBytes += trash.bytes
                        outcome.result.itemsProcessed += 1
                        outcome.moves.append(CleanupMove(
                            title: item.title,
                            originalPath: path,
                            trashPath: trash.trashURL?.path,
                            bytes: trash.bytes,
                            disposal: .trash
                        ))
                    } else {
                        outcome.result.errors.append("Failed: \(item.title)")
                    }
                case .delete:
                    let deleted = CleanSafety.delete(url)
                    if deleted.ok {
                        outcome.result.freedBytes += deleted.bytes
                        outcome.result.itemsProcessed += 1
                        outcome.moves.append(CleanupMove(
                            title: item.title,
                            originalPath: path,
                            trashPath: nil,
                            bytes: deleted.bytes,
                            disposal: .delete
                        ))
                    } else {
                        outcome.result.errors.append("Failed: \(item.title)")
                    }
                }
            }
        }
        return outcome
    }
}
