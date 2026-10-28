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

        // Prefer cached AuthorizationRef. Never fall back to AppleScript here —
        // that would ask for the password again after Touch ID already succeeded.
        let cached = await MainActor.run {
            SessionAuth.shared.runAdmin(launchPath: launchPath, args: args)
        }
        if cached.ok {
            return cached
        }

        if cached.output == "Privileged execute unavailable" {
            // Rare (API stripped). One AppleScript prompt only when session API cannot execute.
            return await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .utility).async {
                    cont.resume(returning: runAdminAppleScript(launchPath: launchPath, args: args))
                }
            }
        }

        return cached
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

        let cached = await MainActor.run {
            SessionAuth.shared.runAdminShell(script)
        }
        if cached.ok || cached.output != "Privileged execute unavailable" {
            return cached
        }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runAdminAppleScript(launchPath: "/bin/bash", args: ["-c", script]))
            }
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

    /// Last resort only when AuthorizationExecuteWithPrivileges is unavailable.
    private static func runAdminAppleScript(launchPath: String, args: [String]) -> (Bool, String) {
        let escapedArgs = args.map { arg -> String in
            let escaped = arg
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " ")

        let shell = "\(launchPath) \(escapedArgs)"
        let escapedShell = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escapedShell)\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error {
                let message = (error[NSAppleScript.errorMessage] as? String)
                    ?? (error["NSAppleScriptErrorMessage"] as? String)
                    ?? error.description
                return (false, message)
            }
            return (true, result.stringValue ?? "")
        }
        return (false, "Failed to create AppleScript")
    }
}
