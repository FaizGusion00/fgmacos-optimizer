import Foundation
import AppKit

enum PrivilegedRunner {
    /// Runs an executable. Admin actions use one system unlock (Touch ID or password), then reuse the session.
    static func run(
        _ launchPath: String,
        args: [String],
        needsAdmin: Bool,
        reason: String = "FGMacOS Optimizer needs permission to optimize your Mac."
    ) async -> (ok: Bool, output: String) {
        if !needsAdmin {
            return await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .utility).async {
                    cont.resume(returning: runProcess(launchPath: launchPath, args: args))
                }
            }
        }

        let authorized = await SessionAuth.shared.ensureAuthorized(reason: reason)
        guard authorized else {
            let msg = await MainActor.run { SessionAuth.shared.lastError } ?? "Authentication cancelled"
            return (false, msg)
        }

        // Cached AuthorizationRef only — AppleScript fallback re-prompts password.
        return await MainActor.run {
            SessionAuth.shared.runAdmin(launchPath: launchPath, args: args)
        }
    }

    /// Multiple root commands in one bash -c — keeps a single elevation for compound actions.
    static func runAdminScript(
        _ script: String,
        reason: String
    ) async -> (ok: Bool, output: String) {
        let authorized = await SessionAuth.shared.ensureAuthorized(reason: reason)
        guard authorized else {
            let msg = await MainActor.run { SessionAuth.shared.lastError } ?? "Authentication cancelled"
            return (false, msg)
        }

        return await MainActor.run {
            SessionAuth.shared.runAdminShell(script)
        }
    }

    private static func runProcess(launchPath: String, args: [String]) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }

}
