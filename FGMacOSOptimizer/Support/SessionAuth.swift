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

    /// Only these durations are valid — picker + persistence always clamp here.
    static let allowedMinutes: [Int] = [5, 10, 15, 30]

    @Published var sessionMinutes: Int {
        didSet {
            let clamped = Self.clampMinutes(sessionMinutes)
            if clamped != sessionMinutes {
                sessionMinutes = clamped
                return
            }
            UserDefaults.standard.set(sessionMinutes, forKey: Keys.sessionMinutes)
            // Changing Remember-for while unlocked resizes the window from unlock time.
            if isUnlocked {
                applyExpiryFromUnlockTime(reason: "duration-changed")
            }
        }
    }

    @Published private(set) var isUnlocked = false
    @Published private(set) var expiresAt: Date?
    /// Forces SwiftUI countdown refresh every second while unlocked.
    @Published private(set) var countdownTick: Int = 0
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
    private var expiryTimer: Timer?
    private var tickTimer: Timer?
    /// Admin commands run off-main; never free the AuthorizationRef while one is in flight.
    private var inFlightAdminRuns = 0
    private var freeWhenIdle = false
    /// 1 Hz countdown only matters while the popover shows the session card.
    private var countdownVisible = false
    private let log = Logger(subsystem: "com.fgmacos.optimizer", category: "auth")

    private enum Keys {
        static let sessionMinutes = "fg.auth.sessionMinutes"
    }

    private static let adminRight = "system.privilege.admin"

    private init() {
        let stored = UserDefaults.standard.object(forKey: Keys.sessionMinutes) as? Int
        sessionMinutes = Self.clampMinutes(stored ?? 10)
        refreshBiometryLabel()
        refreshTouchIDForSudoStatus()
    }

    static func clampMinutes(_ value: Int) -> Int {
        if allowedMinutes.contains(value) { return value }
        // Nearest allowed (e.g. corrupted defaults).
        return allowedMinutes.min(by: { abs($0 - value) < abs($1 - value) }) ?? 10
    }

    var remainingSeconds: Int {
        pruneIfExpired()
        guard let expiresAt, isUnlocked else { return 0 }
        return max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
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
        let probe = await runAdmin(launchPath: "/usr/bin/true", args: [], timeout: 15)
        AuthFileLog.write("root launch probe ok=\(probe.ok) out=\(probe.output.prefix(80))")
        if !probe.ok {
            // Still keep the session if we have a valid AuthorizationRef — commands may work.
            AuthFileLog.write("true probe soft-fail — keeping AuthorizationRef session anyway")
        }

        privilegeVerified = true
        lastProbeDetail = probe.ok ? "admin rights cached" : "admin rights cached (soft probe)"
        unlockedAt = Date()
        isUnlocked = true
        applyExpiryFromUnlockTime(reason: "unlock")
        AuthFileLog.write("UNLOCK OK method=\(unlockMethod.rawValue) for \(sessionMinutes)m expires=\(expiresAt?.description ?? "?") — one prompt")
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
        if inFlightAdminRuns > 0 {
            // A privileged command is still using the ref — free it once idle.
            freeWhenIdle = true
            return
        }
        stopSessionTimers()
        if let authRef {
            AuthorizationFree(authRef, [.destroyRights])
        }
        authRef = nil
        isUnlocked = false
        privilegeVerified = false
        expiresAt = nil
        unlockedAt = nil
        countdownTick &+= 1
        AuthFileLog.write("session locked")
    }

    /// Runs a tool as root using the cached session. The fork + pipe read happen off the
    /// main thread so `purge` / `pmset` never freeze the popover (old Macs: seconds).
    func runAdmin(launchPath: String, args: [String], timeout: TimeInterval = 90) async -> (ok: Bool, output: String) {
        pruneIfExpired()
        guard let authRef else { return (false, "Not authorized") }
        guard AuthExec.isAvailable else { return (false, "Privileged execute unavailable") }
        let handle = AuthHandle(ref: authRef)
        inFlightAdminRuns += 1
        let result: (Bool, String) = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: AuthExec.run(
                    authorization: handle.ref,
                    tool: launchPath,
                    arguments: args,
                    timeout: timeout
                ))
            }
        }
        inFlightAdminRuns -= 1
        if inFlightAdminRuns == 0, freeWhenIdle {
            freeWhenIdle = false
            lock()
        }
        AuthFileLog.write("runAdmin \(launchPath) ok=\(result.0) out=\(result.1.prefix(120))")
        return (ok: result.0, output: result.1)
    }

    func runAdminShell(_ script: String, timeout: TimeInterval = 120) async -> (ok: Bool, output: String) {
        let result = await runAdmin(launchPath: "/bin/bash", args: ["-c", script], timeout: timeout)
        AuthFileLog.write("runAdminShell ok=\(result.ok)")
        return result
    }

    /// Popover open/closed — the countdown tick only runs while someone can see it.
    func setCountdownVisible(_ visible: Bool) {
        countdownVisible = visible
        if visible {
            startTickTimerIfNeeded()
            countdownTick &+= 1
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func startTickTimerIfNeeded() {
        guard countdownVisible, isUnlocked, tickTimer == nil else { return }
        let tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.countdownTick &+= 1 }
        }
        tick.tolerance = 0.2
        tickTimer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    /// Sets `expiresAt = unlockedAt + sessionMinutes`, locks if already past, schedules timers.
    private func applyExpiryFromUnlockTime(reason: String) {
        guard isUnlocked, let unlockedAt else { return }
        let minutes = Self.clampMinutes(sessionMinutes)
        let newExpiry = unlockedAt.addingTimeInterval(TimeInterval(minutes * 60))
        expiresAt = newExpiry
        AuthFileLog.write("session expiry \(reason): \(minutes)m → \(newExpiry)")
        if newExpiry <= Date() {
            AuthFileLog.write("session already past new expiry — locking")
            lock()
            return
        }
        scheduleSessionTimers()
        countdownTick &+= 1
    }

    private func scheduleSessionTimers() {
        stopSessionTimers()
        guard let expiresAt, isUnlocked else { return }
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining > 0 else {
            lock()
            return
        }

        // Exact fire at expiry (not only on next admin action).
        let expiry = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                AuthFileLog.write("session expiry timer fired")
                self?.pruneIfExpired()
            }
        }
        expiryTimer = expiry
        RunLoop.main.add(expiry, forMode: .common)

        // 1 Hz UI tick only while the popover is open (idle CPU: no wakeups when closed).
        startTickTimerIfNeeded()
    }

    private func stopSessionTimers() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func pruneIfExpired() {
        guard isUnlocked, let expiresAt else { return }
        if expiresAt <= Date() {
            AuthFileLog.write("session expired at \(expiresAt)")
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

/// AuthorizationRef is an opaque handle; using it from a worker thread is safe as long as
/// nobody frees it meanwhile (SessionAuth refcounts in-flight runs).
struct AuthHandle: @unchecked Sendable {
    let ref: AuthorizationRef
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

    static func run(
        authorization: AuthorizationRef,
        tool: String,
        arguments: [String],
        timeout: TimeInterval = 90
    ) -> (Bool, String) {
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
        var timedOut = false
        if let pipe {
            // Read until the child closes its stdout (EOF) or the deadline passes.
            // poll() keeps this loop cheap; the caller runs us off the main thread.
            let fd = fileno(pipe)
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            let deadline = Date().addingTimeInterval(timeout)
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            readLoop: while true {
                if Date() >= deadline { timedOut = true; break }
                let r = poll(&pfd, 1, 250)
                if r == 0 { continue }
                if r < 0 {
                    if errno == EINTR { continue }
                    break
                }
                let n = read(fd, &buffer, buffer.count)
                if n > 0 {
                    data.append(buffer, count: n)
                } else if n == 0 {
                    break readLoop
                } else if errno != EINTR {
                    break readLoop
                }
            }
            output = String(data: data, encoding: .utf8) ?? ""
            fclose(pipe)
        }

        if timedOut {
            return (false, "timed out after \(Int(timeout))s")
        }
        return (status == errAuthorizationSuccess, output)
    }
}
