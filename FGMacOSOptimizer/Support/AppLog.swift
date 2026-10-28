import Foundation
import OSLog

enum AppLog {
    static let turbo = Logger(subsystem: "com.fgmacos.optimizer", category: "turbo")
    static let cleaner = Logger(subsystem: "com.fgmacos.optimizer", category: "cleaner")
    static let watchdog = Logger(subsystem: "com.fgmacos.optimizer", category: "watchdog")
    static let metrics = Logger(subsystem: "com.fgmacos.optimizer", category: "metrics")
}
