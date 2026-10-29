import Foundation
import LocalAuthentication
import Security
import Combine
import OSLog
import Darwin

enum AdminUnlockMethod: String {
    case touchID
    case password
    case unknown
}

/// Real admin session: Touch ID (LA) → admin rights → verified root probe (`id -u` == 0).
/// Note: `com.apple.security.sudo` is entitled-only (-60005 for 3rd party apps) — never use it.
@MainActor
final class SessionAuth: ObservableObject {
    static let shared = SessionAuth()

    @Published var sessionMinutes: Int {
        didSet {
            UserDefaults.standard.set(sessionMinutes, forKey: Keys.sessionMinutes)
            if isUnlocked, let unlockedAt {
                expiresAt = unlockedAt.addingTimeInterval(TimeInterval(sessionMinutes * 60))
            }
        }
    }

    @Published private(set) var isUnlocked = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var biometryLabel: String = "Touch ID"
    @Published private(set) var unlockMethod: AdminUnlockMethod = .unknown
    @Published private(set) var privilegeVerified = false
    @Published private(set) var lastProbeDetail: String?
    @Published private(set) var touchIDForSudoEnabled = false
    @Published var lastError: String?
    @Published var isBusy = false

    private var unlockedAt: Date?
    private var authRef: AuthorizationRef?
    private var unlockTask: Task<Bool, Never>?
    private let log = Logger(subsystem: "com.fgmacos.optimizer", category: "auth")

    private enum Keys {
        static let sessionMinutes = "fg.auth.sessionMinutes"
    }

    /// Right used by AuthorizationExecuteWithPrivileges (see authorization.plist).
    private static let adminRight = "system.privilege.admin"

    private init() {
        let stored = UserDefaults.standard.object(forKey: Keys.sessionMinutes) as? Int
        sessionMinutes = stored ?? 10
        refreshBiometryLabel()
        refreshTouchIDForSudoStatus()
    }

    var remainingSeconds: Int {
        guard let expiresAt else { return 0 }
        return max(0, Int(expiresAt.timeIntervalSinceNow))
    }

    var isSessionValid: Bool {
        pruneIfExpired()
        return isUnlocked && privilegeVerified && authRef != nil
    }

    /// Cached — do not recreate LAContext every TimelineView tick (was spamming authd every 1s).
    private(set) var prefersBiometrics: Bool = false

    func refreshBiometryLabel() {
        let context = LAContext()
        prefersBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: biometryLabel = "Touch ID"
        case .faceID: biometryLabel = "Face ID"
        default:
            if #available(macOS 14.0, *), context.biometryType == .opticID {
                biometryLabel = "Optic ID"
            } else {
                biometryLabel = "Password"
            }
        }
    }

    func refreshTouchIDForSudoStatus() {
        let path = "/etc/pam.d/sudo_local"
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            touchIDForSudoEnabled = false
            return
        }
        let enabled = data
            .split(separator: "\n")
            .contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("#") && t.contains("pam_tid.so")
            }
        touchIDForSudoEnabled = enabled
    }

    /// Unlock: Touch ID (when available) → admin authorization → root probe.
    func ensureAuthorized(reason: String) async -> Bool {
        if isSessionValid { return true }

        if let unlockTask {
            return await unlockTask.value
        }

        let task = Task { @MainActor in
            await self.performUnlock(reason: reason)
        }
        unlockTask = task
        let ok = await task.value
        unlockTask = nil
        return ok
    }

    private func performUnlock(reason: String) async -> Bool {
        if isSessionValid { return true }

        isBusy = true
        defer { isBusy = false }

        refreshBiometryLabel()
        lastError = nil
        privilegeVerified = false
        lastProbeDetail = nil
        unlockMethod = .unknown

        AuthFileLog.write("unlock start — biometry=\(biometryLabel) reason=\(reason)")
        log.info("Unlock start biometry=\(self.biometryLabel, privacy: .public)")

        // 1) Touch ID / biometrics when available (this is the fingerprint sheet).
        var usedBiometrics = false
        if prefersBiometrics {
            do {
                try await authenticateOwner(reason: reason)
                usedBiometrics = true
                unlockMethod = .touchID
                AuthFileLog.write("LA biometrics OK (\(biometryLabel))")
                log.info("LA biometrics OK")
            } catch {
                // Fall through to password-capable admin sheet.
                AuthFileLog.write("LA biometrics failed: \(error.localizedDescription) — continue to admin sheet")
                log.error("LA failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2) Admin right for AuthorizationExecuteWithPrivileges (root tools).
        //    macOS often shows a password field here — that is a system SecurityAgent dialog,
        //    not something we can force to Touch ID without Apple entitlements.
        do {
            try obtainAdminAuthorization()
            if !usedBiometrics { unlockMethod = .password }
            AuthFileLog.write("AuthorizationCopyRights(system.privilege.admin) OK")
            log.info("Admin right OK")
        } catch {
            lastError = error.localizedDescription
            AuthFileLog.write("Admin right FAILED: \(error.localizedDescription)")
            log.error("Admin right failed: \(error.localizedDescription, privacy: .public)")
            lock()
            return false
        }

        // 3) Prove we can actually run as root — otherwise UI would lie.
        let probe = runAdmin(launchPath: "/usr/bin/id", args: ["-u"])
        let uid = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
        AuthFileLog.write("root probe ok=\(probe.ok) output=\(uid.isEmpty ? "<empty>" : uid)")
        log.info("Root probe ok=\(probe.ok) uid=\(uid, privacy: .public)")

        guard probe.ok, uid == "0" else {
            // AuthExec broken on this OS — try one AppleScript probe (may re-prompt).
            AuthFileLog.write("AuthExec probe failed — trying AppleScript fallback probe")
            let scriptProbe = await runAppleScriptProbe()
            if scriptProbe {
                privilegeVerified = true
                lastProbeDetail = "root via AppleScript"
                unlockedAt = Date()
                expiresAt = Date().addingTimeInterval(TimeInterval(sessionMinutes * 60))
                isUnlocked = true
                AuthFileLog.write("Unlocked with AppleScript fallback (AuthExec unavailable)")
                return true
            }

            lastError = "Admin dialog OK, but privileged run failed (uid=\(uid.isEmpty ? "none" : uid)). AuthExec may be blocked on this macOS."
            AuthFileLog.write("UNLOCK FAILED — privilege not verified")
            lock()
            return false
        }

        privilegeVerified = true
        lastProbeDetail = "uid=0 verified"
        unlockedAt = Date()
        expiresAt = Date().addingTimeInterval(TimeInterval(sessionMinutes * 60))
        isUnlocked = true
        AuthFileLog.write("UNLOCK OK method=\(unlockMethod.rawValue) for \(sessionMinutes)m")
        log.info("Session unlocked method=\(self.unlockMethod.rawValue, privacy: .public) minutes=\(self.sessionMinutes)")
        return true
    }

    /// One-time: enable `pam_tid` so Terminal `sudo` can use Touch ID.
    /// Does not change AuthorizationExecuteWithPrivileges dialogs (those stay SecurityAgent).
    func enableTouchIDForSudo() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        lastError = nil

        let script = """
        do shell script "printf '%s\\n' '# Managed by FGMacOS Optimizer' 'auth       sufficient     pam_tid.so' > /etc/pam.d/sudo_local && chmod 644 /etc/pam.d/sudo_local" with administrator privileges
        """
        AuthFileLog.write("enableTouchIDForSudo start")
        let result = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    _ = appleScript.executeAndReturnError(&error)
                    if let error {
                        let message = (error[NSAppleScript.errorMessage] as? String) ?? "Failed"
                        cont.resume(returning: (false, message))
                    } else {
                        cont.resume(returning: (true, ""))
                    }
                } else {
                    cont.resume(returning: (false, "AppleScript unavailable"))
                }
            }
        }
        refreshTouchIDForSudoStatus()
        if result.0 {
            AuthFileLog.write("enableTouchIDForSudo OK")
        } else {
            lastError = result.1
            AuthFileLog.write("enableTouchIDForSudo FAIL: \(result.1)")
        }
        return result.0
    }

    func lock() {
        if let authRef {
            AuthorizationFree(authRef, [.destroyRights])
        }
        authRef = nil
        isUnlocked = false
        privilegeVerified = false
        expiresAt = nil
        unlockedAt = nil
        AuthFileLog.write("session locked")
    }

    func runAdmin(launchPath: String, args: [String]) -> (ok: Bool, output: String) {
        pruneIfExpired()
        guard let authRef else { return (false, "Not authorized") }
        guard AuthExec.isAvailable else { return (false, "Privileged execute unavailable") }
        let result = AuthExec.run(authorization: authRef, tool: launchPath, arguments: args)
        AuthFileLog.write("runAdmin \(launchPath) ok=\(result.0) out=\(result.1.prefix(120))")
        return (ok: result.0, output: result.1)
    }

    func runAdminShell(_ script: String) -> (ok: Bool, output: String) {
        pruneIfExpired()
        guard let authRef else { return (false, "Not authorized") }
        guard AuthExec.isAvailable else { return (false, "Privileged execute unavailable") }
        let result = AuthExec.run(authorization: authRef, tool: "/bin/bash", arguments: ["-c", script])
        AuthFileLog.write("runAdminShell ok=\(result.0) out=\(result.1.prefix(120))")
        return (ok: result.0, output: result.1)
    }

    private func pruneIfExpired() {
        if let expiresAt, expiresAt <= Date() {
            AuthFileLog.write("session expired")
            lock()
        }
    }

    private func authenticateOwner(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password…"
        context.localizedFallbackTitle = "Password"
        // Short reuse avoids double-prompt if SecurityAgent also hits biometrics quickly.
        context.touchIDAuthenticationAllowableReuseDuration = 30

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw error ?? AuthError.biometricsUnavailable
        }
        try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
    }

    private func obtainAdminAuthorization() throws {
        if let authRef {
            AuthorizationFree(authRef, [])
            self.authRef = nil
        }

        var ref: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &ref)
        guard status == errAuthorizationSuccess, let ref else {
            throw AuthError.authorizationFailed(status)
        }

        status = Self.adminRight.withCString { namePtr in
            var item = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .extendRights]
                return AuthorizationCopyRights(ref, &rights, nil, flags, nil)
            }
        }

        guard status == errAuthorizationSuccess else {
            AuthorizationFree(ref, [])
            throw AuthError.authorizationFailed(status)
        }
        self.authRef = ref
    }

    private func runAppleScriptProbe() async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = "do shell script \"id -u\" with administrator privileges"
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else {
                    cont.resume(returning: false)
                    return
                }
                let result = appleScript.executeAndReturnError(&error)
                let uid = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: error == nil && uid == "0")
            }
        }
    }
}

enum AuthError: LocalizedError {
    case biometricsUnavailable
    case authorizationFailed(OSStatus)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .biometricsUnavailable:
            return "Biometrics unavailable on this Mac."
        case .authorizationFailed(let status):
            if status == errAuthorizationCanceled { return "Authentication cancelled." }
            if status == -60005 { return "Authorization denied (-60005)." }
            return "Administrator authorization failed (\(status))."
        case .cancelled:
            return "Cancelled."
        }
    }
}

// MARK: - AuthorizationExecuteWithPrivileges (dlsym)

enum AuthExec {
    private typealias ExecFn = @convention(c) (
        AuthorizationRef?,
        UnsafePointer<CChar>?,
        AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static let execFn: ExecFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else {
            return nil
        }
        guard let sym = dlsym(handle, "AuthorizationExecuteWithPrivileges") else {
            return nil
        }
        return unsafeBitCast(sym, to: ExecFn.self)
    }()

    static var isAvailable: Bool { execFn != nil }

    static func run(authorization: AuthorizationRef, tool: String, arguments: [String]) -> (Bool, String) {
        guard let execFn else {
            return (false, "Privileged execute unavailable")
        }

        var cArgs = ([tool] + arguments).map { strdup($0) }
        cArgs.append(nil)
        defer {
            for ptr in cArgs where ptr != nil { free(ptr) }
        }

        var pipe: UnsafeMutablePointer<FILE>?
        let status = cArgs.withUnsafeMutableBufferPointer { buf -> OSStatus in
            guard let base = buf.baseAddress else { return OSStatus(errAuthorizationInternal) }
            return tool.withCString { toolPath in
                execFn(authorization, toolPath, [], base, &pipe)
            }
        }

        var output = ""
        if let pipe {
            let fd = fileno(pipe)
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(fd, &buffer, buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            output = String(data: data, encoding: .utf8) ?? ""
            fclose(pipe)
        }

        return (status == errAuthorizationSuccess, output)
    }
}
