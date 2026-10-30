import Foundation

struct WatchdogItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable, Hashable {
        case hog
        case elevated
        case hung
    }

    let id: String
    let pid: Int32
    let name: String
    let bundleID: String?
    let kind: Kind
    let cpuPercent: Double
    let firstSeen: Date

    var detail: String {
        switch kind {
        case .hog:
            return String(format: "%.0f%% CPU · hog", cpuPercent)
        case .elevated:
            return String(format: "%.0f%% CPU · elevated", cpuPercent)
        case .hung:
            let seconds = Int(Date().timeIntervalSince(firstSeen))
            return "Not responding · \(seconds)s"
        }
    }
}

struct TopProcess: Identifiable, Equatable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double
}
