import Foundation
import Combine

struct TurboActivationResult {
    var error: String?
}

@MainActor
final class TurboModeEngine: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    /// Live `mdutil -s /` — true when indexing is disabled (Turbo's real effect).
    @Published private(set) var indexingDisabledVerified = false
    @Published private(set) var lastVerifiedDetail: String = "Not checked"

    private var didDisableSpotlight = false
    private var clearedDerivedData = false

    /// Sync UI with real Spotlight state after relaunch.
    func syncFromSystem() {
        refreshIndexingStatus()
        if indexingDisabledVerified {
            isActive = true
            didDisableSpotlight = true
            AppLog.turbo.info("Synced Turbo ON from system (Spotlight indexing disabled)")
        }
    }

    func refreshIndexingStatus() {
        let status = Self.spotlightIndexingStatus()
        indexingDisabledVerified = status.disabled
        lastVerifiedDetail = status.detail
    }

    private static func isSpotlightIndexingDisabled() -> Bool {
        spotlightIndexingStatus().disabled
    }

    private static func spotlightIndexingStatus() -> (disabled: Bool, detail: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        process.arguments = ["-s", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let disabled = out.localizedCaseInsensitiveContains("Indexing disabled")
            let detail = disabled ? "mdutil: Indexing disabled" : (out.isEmpty ? "mdutil: unknown" : "mdutil: \(out)")
            return (disabled, detail)
        } catch {
            return (false, "mdutil check failed")
        }
    }

    func activate() async -> TurboActivationResult {
        statusMessage = "Enabling Turbo Mode…"

        statusMessage = "Pausing Spotlight indexing…"
        let spot = await PrivilegedRunner.run(
            "/usr/bin/mdutil",
            args: ["-a", "-i", "off"],
            needsAdmin: true,
            reason: "Enable Turbo Mode — pause Spotlight indexing."
        )
        if spot.ok {
            didDisableSpotlight = true
            AppLog.turbo.info("Spotlight indexing disabled via mdutil")
            refreshIndexingStatus()
        } else if spot.output.lowercased().contains("cancel") || spot.output.lowercased().contains("user") {
            statusMessage = nil
            AppLog.turbo.error("Turbo cancelled — admin denied for mdutil")
            return TurboActivationResult(error: "Turbo Mode cancelled — admin permission was denied.")
        } else {
            statusMessage = "Spotlight pause skipped (no admin)…"
            let err = spot.output
            AppLog.turbo.error("mdutil failed: \(err, privacy: .public)")
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        statusMessage = "Stopping Time Machine backup…"
        let tm = await PrivilegedRunner.run(
            "/usr/bin/tmutil",
            args: ["stopbackup"],
            needsAdmin: false
        )
        AppLog.turbo.info("tmutil stopbackup ok=\(tm.ok)")

        statusMessage = "Cleaning Xcode Derived Data…"
        clearedDerivedData = await clearDerivedData()
        AppLog.turbo.info("DerivedData cleared=\(self.clearedDerivedData)")

        isActive = true
        statusMessage = clearedDerivedData ? "Turbo Mode on — Derived Data cleared" : "Turbo Mode on"
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        statusMessage = nil
        return TurboActivationResult(error: nil)
    }

    func deactivate() async {
        statusMessage = "Restoring system services…"

        if didDisableSpotlight {
            statusMessage = "Re-enabling Spotlight…"
            _ = await PrivilegedRunner.run(
                "/usr/bin/mdutil",
                args: ["-a", "-i", "on"],
                needsAdmin: true,
                reason: "Turn off Turbo Mode — restore Spotlight indexing."
            )
            didDisableSpotlight = false
            refreshIndexingStatus()
        }

        isActive = false
        statusMessage = "Turbo Mode off"
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        statusMessage = nil
    }

    private func clearDerivedData() async -> Bool {
        let path = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let contents = try fm.contentsOfDirectory(atPath: path)
                    for item in contents {
                        // Skip hidden / in-use lock folders carefully
                        if item.hasPrefix(".") { continue }
                        let full = (path as NSString).appendingPathComponent(item)
                        try? fm.removeItem(atPath: full)
                    }
                    cont.resume(returning: true)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }
}
