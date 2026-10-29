import Foundation
import OSLog

enum AppLog {
    static let turbo = Logger(subsystem: "com.fgmacos.optimizer", category: "turbo")
    static let cleaner = Logger(subsystem: "com.fgmacos.optimizer", category: "cleaner")
    static let watchdog = Logger(subsystem: "com.fgmacos.optimizer", category: "watchdog")
    static let metrics = Logger(subsystem: "com.fgmacos.optimizer", category: "metrics")
    static let life = Logger(subsystem: "com.fgmacos.optimizer", category: "life")

    /// Always-on file trail for “why did it quit?” on user Macs.
    static func lifeFile(_ message: String) {
        AuthFileLog.write("[life] \(message)")
        life.info("\(message, privacy: .public)")
    }
}
