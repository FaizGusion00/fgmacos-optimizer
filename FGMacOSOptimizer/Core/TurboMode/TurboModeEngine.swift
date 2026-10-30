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
    /// Extra IDE/tool caches help older Macs where Spotlight crawls for hours.
    static var heavyExclusionPaths: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/Library/Developer/Xcode/DerivedData",
            home + "/Library/Developer/CoreSimulator",
            home + "/Library/Developer/Xcode/iOS DeviceSupport",
            home + "/Library/pnpm",
            home + "/Library/Containers/com.docker.docker/Data",
            home + "/Library/Application Support/Code/CachedData",
            home + "/Library/Application Support/Code/CachedExtensionVSIXs",
            home + "/Library/Application Support/Code/Cache",
            home + "/Library/Application Support/Code/Code Cache",
            home + "/Library/Application Support/Cursor/CachedData",
            home + "/Library/Application Support/Cursor/CachedExtensionVSIXs",
            home + "/Library/Application Support/Cursor/Cache",
            home + "/Library/Application Support/Cursor/Code Cache",
            home + "/.npm/_cacache",
            home + "/.cache",
            home + "/.cargo/registry/cache",
            home + "/.gradle/caches",
            home + "/go/pkg/mod",
            home + "/.m2/repository",
            home + "/.pub-cache"
        ]
    }

    private var statusCache: (at: Date, value: (disabled: Bool, detail: String))?
    private var backgroundRefresh: Task<Void, Never>?

    /// Apply heavy-folder exclusions without toggling Turbo UI state (safe always-on for old Macs).
    @discardableResult
    func ensureHeavyExclusions() async -> Int {
        let count = await applyHeavyExclusions()
        exclusionCount = count
        await refreshIndexingStatus()
        return count
    }

    init() {
        isActive = UserDefaults.standard.bool(forKey: Keys.active)
        exclusionCount = verifiedExclusionPaths().count
    }

    /// Sync UI + one-shot repair if old Turbo left volume indexing disabled.
    func syncFromSystem() async {
        await refreshIndexingStatus()
        if volumeIndexingDisabled {
            await repairLegacyVolumeIndexingIfNeeded()
            statusCache = nil
            await refreshIndexingStatus()
        }
        isActive = UserDefaults.standard.bool(forKey: Keys.active)
    }

    /// Awaitable status refresh — `mdutil -s /` runs on a utility queue (never blocks the UI).
    func refreshIndexingStatus() async {
        let status = await volumeStatus()
        applyStatus(status)
    }

    /// Fire-and-forget, coalesced — for popover open (result not needed synchronously).
    func refreshIndexingStatusInBackground() {
        guard backgroundRefresh == nil else { return }
        backgroundRefresh = Task { [weak self] in
            await self?.refreshIndexingStatus()
            self?.backgroundRefresh = nil
        }
    }

    private func volumeStatus(maxAge: TimeInterval = 10) async -> (disabled: Bool, detail: String) {
        if let cached = statusCache, Date().timeIntervalSince(cached.at) < maxAge {
            return cached.value
        }
        let value = await Self.probeSpotlightVolumeStatus()
        statusCache = (Date(), value)
        return value
    }

    private func applyStatus(_ status: (disabled: Bool, detail: String)) {
        volumeIndexingDisabled = status.disabled
        let applied = verifiedExclusionPaths().count
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

    nonisolated private static func probeSpotlightVolumeStatus() async -> (disabled: Bool, detail: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: spotlightVolumeStatusSync())
            }
        }
    }

    nonisolated private static func spotlightVolumeStatusSync() -> (disabled: Bool, detail: String) {
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
        statusCache = nil
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

        statusMessage = "Pausing Time Machine backup…"
        let tmPaused = await TimeMachineStatus.stopBackupIfRunning()
        AppLog.turbo.info("tmutil stopbackup paused=\(tmPaused)")

        var clearedDD = false
        if clearDerivedData {
            statusMessage = "Cleaning Xcode Derived Data…"
            clearedDD = await clearDerivedDataFolder()
            AppLog.turbo.info("DerivedData cleared=\(clearedDD)")
        }

        await refreshIndexingStatus()
        if volumeIndexingDisabled {
            await repairLegacyVolumeIndexingIfNeeded()
            await refreshIndexingStatus()
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
        await refreshIndexingStatus()
        statusMessage = "Turbo off — Spotlight volume unchanged (no reindex)"
        try? await Task.sleep(nanoseconds: 900_000_000)
        statusMessage = nil
        AppLog.turbo.info("Soft Turbo deactivated — volume indexing left alone")
    }

    /// App quit: never restore via mdutil -a (avoids reindex storm).
    func detachWithoutRestoringSpotlight() {
        AppLog.turbo.info("App quit — skipping Spotlight restore (no mdutil -a)")
    }

    /// Writes `.metadata_never_index` markers into heavy folders that exist. No admin, no
    /// per-folder `mdutil -i off` (that is a no-op on modern macOS: "unknown indexing state")
    /// and never `mdutil -a`. Returns the number of folders whose marker is present now.
    @discardableResult
    private func applyHeavyExclusions() async -> Int {
        let candidates = Self.heavyExclusionPaths
        let existing = appliedExclusionPaths()
        let (applied, verified): ([String], Int) = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager()
                var list = existing
                var ok = 0
                for path in candidates {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let marker = (path as NSString).appendingPathComponent(".metadata_never_index")
                    if !fm.fileExists(atPath: marker) {
                        _ = fm.createFile(atPath: marker, contents: Data(), attributes: nil)
                    }
                    if fm.fileExists(atPath: marker) {
                        ok += 1
                        if !list.contains(path) { list.append(path) }
                    }
                }
                cont.resume(returning: (list, ok))
            }
        }
        UserDefaults.standard.set(applied, forKey: Keys.exclusionsApplied)
        AppLog.turbo.info("heavy exclusions verified=\(verified) tracked=\(applied.count)")
        return verified
    }

    private func appliedExclusionPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.exclusionsApplied) ?? []
    }

    /// Paths we track whose marker file is actually present (honest count for the UI).
    private func verifiedExclusionPaths() -> [String] {
        appliedExclusionPaths().filter {
            FileManager.default.fileExists(atPath: ($0 as NSString).appendingPathComponent(".metadata_never_index"))
        }
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
