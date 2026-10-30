import Foundation

/// Honest Time Machine handling: only claim "paused" when a backup was really running.
enum TimeMachineStatus {
    /// `tmutil status` prints `Running = 1;` while a backup is in progress.
    static func isBackupRunning() async -> Bool {
        let result = await PrivilegedRunner.run("/usr/bin/tmutil", args: ["status"], needsAdmin: false)
        guard result.ok else { return false }
        return result.output.contains("Running = 1")
    }

    /// Stops an in-progress backup. Returns true only if one was running and the stop succeeded.
    static func stopBackupIfRunning() async -> Bool {
        guard await isBackupRunning() else { return false }
        let stop = await PrivilegedRunner.run("/usr/bin/tmutil", args: ["stopbackup"], needsAdmin: false)
        return stop.ok
    }
}
