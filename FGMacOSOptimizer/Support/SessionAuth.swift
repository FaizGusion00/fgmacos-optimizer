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

/// One admin unlock for the session.
///
/// Log evidence (macOS 27): we used to call LocalAuthentication Touch ID, then
/// `AuthorizationCopyRights` (SecurityAgent: "TouchID is not enabled" → password),
/// then AppleScript because AuthExec stdout was empty → **3 prompts**.
/// Now: single SecurityAgent admin sheet only; never AppleScript during unlock.
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
        touchIDForSudoEnabled = data
            .split(separator: "\n")
            .contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("#") && t.contains("pam_tid.so")
            }
    }

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

        AuthFileLog.write("unlock start — single admin sheet only (no LA, no AppleScript) reason=\(reason)")
        log.info("Unlock start — single admin authorization")

        // ONE SecurityAgent dialog. Do NOT call LocalAuthentication first —
        // that was Touch ID, then password (SecurityAgent: TouchID is not enabled).
        do {
            try obtainAdminAuthorization()
            unlockMethod = .password
            AuthFileLog.write("AuthorizationCopyRights(system.privilege.admin) OK")
            log.info("Admin right OK")
        } catch {
            lastError = error.localizedDescription
            AuthFileLog.write("Admin right FAILED: \(error.localizedDescription)")
            log.error("Admin right failed: \(error.localizedDescription, privacy: .public)")
            lock()
            return false
        }

        // AuthExec often returns empty stdout on modern macOS even when launch succeeds.
        // Never fall back to AppleScript here — that caused the 2nd/3rd password prompt.
        let probe = runAdmin(launchPath: "/usr/bin/true", args: [])
        AuthFileLog.write("root launch probe ok=\(probe.ok) out=\(probe.output.prefix(80))")
        if !probe.ok {
            // Still keep the session if we have a valid AuthorizationRef — commands may work.
            AuthFileLog.write("true probe soft-fail — keeping AuthorizationRef session anyway")
        }

        privilegeVerified = true
        lastProbeDetail = probe.ok ? "admin rights cached" : "admin rights cached (soft probe)"
        unlockedAt = Date()
        expiresAt = Date().addingTimeInterval(TimeInterval(sessionMinutes * 60))
        isUnlocked = true
        AuthFileLog.write("UNLOCK OK method=\(unlockMethod.rawValue) for \(sessionMinutes)m — one prompt")
        log.info("Session unlocked for \(self.sessionMinutes)m (single prompt)")
        return true
    }

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
            // Brief wait — AEWP can return before child writes.
            for _ in 0..<20 {
                let n = read(fd, &buffer, buffer.count)
                if n > 0 {
                    data.append(buffer, count: n)
                } else if n == 0 {
                    break
                } else {
                    usleep(20_000)
                }
            }
            output = String(data: data, encoding: .utf8) ?? ""
            fclose(pipe)
        }

        return (status == errAuthorizationSuccess, output)
    }
}
