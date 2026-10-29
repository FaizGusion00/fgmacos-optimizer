import Foundation
import Combine

struct TurboActivationResult {
    var error: String?
}

/// Soft Turbo: exclude heavy folders from Spotlight + stop TM backup.
/// Never toggles volume-wide `mdutil -a -i off/on` (that causes reindex storms).
@MainActor
final class TurboModeEngine: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    /// True when volume Spotlight indexing is disabled (legacy / unexpected).
    @Published private(set) var volumeIndexingDisabled = false
    @Published private(set) var lastVerifiedDetail: String = "Not checked"
    @Published private(set) var exclusionCount = 0
    @Published private(set) var migratedLegacyIndexing = false

    private enum Keys {
        static let active = "fg.turbo.softActive.v1"
        static let exclusionsApplied = "fg.turbo.exclusionsApplied.v1"
        static let legacyRepairDone = "fg.turbo.legacyVolumeRepair.v1"
    }

    /// Heavy paths safe to permanently keep out of Spotlight (no volume reindex on Turbo OFF).
    static var heavyExclusionPaths: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Library/Caches",
            home + "/Library/Developer/Xcode/DerivedData",
            home + "/Library/Developer/CoreSimulator",
            home + "/Library/Developer/Xcode/iOS DeviceSupport",
            home + "/Library/pnpm",
            home + "/Library/Containers/com.docker.docker/Data",
            home + "/.npm/_cacache",
            home + "/.cache"
        ]
    }

    init() {
        isActive = UserDefaults.standard.bool(forKey: Keys.active)
        exclusionCount = (UserDefaults.standard.stringArray(forKey: Keys.exclusionsApplied) ?? []).count
    }

    /// Sync UI + one-shot repair if old Turbo left volume indexing disabled.
    func syncFromSystem() async {
        refreshIndexingStatus()
        if volumeIndexingDisabled {
            await repairLegacyVolumeIndexingIfNeeded()
            refreshIndexingStatus()
        }
        isActive = UserDefaults.standard.bool(forKey: Keys.active)
        exclusionCount = appliedExclusionPaths().count
        refreshIndexingStatus()
    }

    func refreshIndexingStatus() {
        let status = Self.spotlightVolumeStatus()
        volumeIndexingDisabled = status.disabled
        let applied = appliedExclusionPaths().count
        exclusionCount = applied
        if status.disabled {
            lastVerifiedDetail = "Volume indexing disabled (legacy)"
        } else if isActive {
            lastVerifiedDetail = "Turbo soft · \(applied) heavy folders excluded · volume indexing ON"
        } else {
            lastVerifiedDetail = applied > 0
                ? "Volume indexing ON · \(applied) cache folders stay excluded"
                : status.detail
        }
    }

    /// Soft Turbo active (kept for existing UI bindings).
    var indexingDisabledVerified: Bool { isActive }

    private static func spotlightVolumeStatus() -> (disabled: Bool, detail: String) {
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

    /// If pre-1.10.1 Turbo left `mdutil -a -i off`, turn volume indexing back on once.
    func repairLegacyVolumeIndexingIfNeeded() async {
        guard volumeIndexingDisabled else { return }
        statusMessage = "Restoring Spotlight after old Turbo…"
        let result = await PrivilegedRunner.run(
            "/usr/bin/mdutil",
            args: ["-a", "-i", "on"],
            needsAdmin: true,
            reason: "Restore Spotlight indexing left disabled by an older Turbo Mode."
        )
        UserDefaults.standard.set(true, forKey: Keys.legacyRepairDone)
        migratedLegacyIndexing = result.ok
        AppLog.turbo.info("Legacy volume indexing repair ok=\(result.ok) out=\(result.output, privacy: .public)")
        statusMessage = result.ok ? "Spotlight volume indexing restored" : "Could not restore Spotlight (admin denied)"
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        statusMessage = nil
    }

    func activate(clearDerivedData: Bool = false) async -> TurboActivationResult {
        statusMessage = "Enabling Turbo Mode…"

        statusMessage = "Excluding heavy folders from Spotlight…"
        let excluded = await applyHeavyExclusions()
        exclusionCount = excluded
        UserDefaults.standard.set(true, forKey: Keys.active)
        AppLog.turbo.info("Soft Turbo exclusions applied count=\(excluded)")

        statusMessage = "Stopping Time Machine backup…"
        let tm = await PrivilegedRunner.run(
            "/usr/bin/tmutil",
            args: ["stopbackup"],
            needsAdmin: false
        )
        AppLog.turbo.info("tmutil stopbackup ok=\(tm.ok)")

        var clearedDD = false
        if clearDerivedData {
            statusMessage = "Cleaning Xcode Derived Data…"
            clearedDD = await clearDerivedDataFolder()
            AppLog.turbo.info("DerivedData cleared=\(clearedDD)")
        }

        refreshIndexingStatus()
        if volumeIndexingDisabled {
            await repairLegacyVolumeIndexingIfNeeded()
            refreshIndexingStatus()
        }

        isActive = true
        statusMessage = clearedDD
            ? "Turbo on — heavy folders excluded · Derived Data cleared"
            : "Turbo on — heavy folders excluded · Spotlight volume stays ON"
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        statusMessage = nil
        return TurboActivationResult(error: nil)
    }

    /// Soft OFF: clear active flag only. Keep permanent cache exclusions (no reindex storm).
    func deactivate() async {
        statusMessage = "Turning Turbo off…"
        UserDefaults.standard.set(false, forKey: Keys.active)
        isActive = false
        refreshIndexingStatus()
        statusMessage = "Turbo off — Spotlight volume unchanged (no reindex)"
        try? await Task.sleep(nanoseconds: 900_000_000)
        statusMessage = nil
        AppLog.turbo.info("Soft Turbo deactivated — volume indexing left alone")
    }

    /// App quit: never restore via mdutil -a (avoids reindex storm).
    func detachWithoutRestoringSpotlight() {
        AppLog.turbo.info("App quit — skipping Spotlight restore (no mdutil -a)")
    }

    @discardableResult
    private func applyHeavyExclusions() async -> Int {
        let fm = FileManager.default
        var existing = appliedExclusionPaths()
        var targets: [String] = []

        // Markers do not need admin.
        for path in Self.heavyExclusionPaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            targets.append(path)
            let marker = (path as NSString).appendingPathComponent(".metadata_never_index")
            if !fm.fileExists(atPath: marker) {
                _ = fm.createFile(atPath: marker, contents: Data(), attributes: nil)
            }
            if !existing.contains(path) { existing.append(path) }
        }

        // Path-level only (never mdutil -a). User-owned trees usually work without admin.
        for path in targets {
            let md = await PrivilegedRunner.run(
                "/usr/bin/mdutil",
                args: ["-i", "off", path],
                needsAdmin: false
            )
            if !md.ok {
                AppLog.turbo.info("mdutil -i off soft-fail \(path, privacy: .public)")
            }
        }

        UserDefaults.standard.set(existing, forKey: Keys.exclusionsApplied)
        return existing.count
    }

    private func appliedExclusionPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.exclusionsApplied) ?? []
    }

    private func clearDerivedDataFolder() async -> Bool {
        let path = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let contents = try fm.contentsOfDirectory(atPath: path)
                    for item in contents {
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
