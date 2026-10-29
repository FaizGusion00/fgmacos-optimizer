import Foundation
import AppKit
import Combine

@MainActor
final class CleanerStore: ObservableObject {
    static let shared = CleanerStore()

    @Published var tab: CleanCategory = .smartCare
    @Published var items: [CleanItem] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var status: String?
    @Published var lastResult: CleanRunResult?
    @Published var installedApps: [InstalledApp] = []
    @Published var selectedApp: InstalledApp?
    @Published var startupItems: [StartupItem] = []
    @Published var snapshots: [LocalSnapshot] = []
    @Published var spaceNodes: [SpaceNode] = []
    @Published var includeBrowserHistory = false
    @Published var duplicatesEnabled = false

    private let smart = SmartCareEngine()
    private let uninstaller = AppUninstaller()
    private let largeOld = LargeOldScanner()
    private let duplicates = DuplicateScanner()
    private let login = LoginItemsManager()
    private let snaps = SnapshotManager()
    private let dev = DevCleanupPack()
    private let mail = MailMessagesCleaner()
    private let lens = SpaceLensScanner()
    private let browser = BrowserCleanup()

    var selectedBytes: UInt64 {
        items.filter(\.selected).reduce(0) { $0 + $1.bytes }
    }

    func selectTab(_ tab: CleanCategory) {
        self.tab = tab
        Task { await refresh() }
    }

    func refresh() async {
        isScanning = true
        status = "Scanning…"
        lastResult = nil
        defer {
            isScanning = false
            if status == "Scanning…" { status = nil }
        }

        switch tab {
        case .smartCare:
            items = await smart.scan()
        case .uninstaller:
            installedApps = await uninstaller.listApps()
            if let selectedApp {
                items = await uninstaller.leftovers(for: selectedApp)
            } else {
                items = []
            }
        case .largeOld:
            items = await largeOld.scan()
        case .duplicates:
            guard duplicatesEnabled else {
                items = []
                status = "Enable scan to find duplicates in Downloads (slow)."
                return
            }
            items = await duplicates.scan()
        case .loginItems:
            startupItems = await login.list()
            items = []
        case .snapshots:
            snapshots = await snaps.list()
            items = []
        case .dev:
            items = await dev.scan()
        case .mailMessages:
            items = await mail.scan()
            if items.isEmpty {
                status = "No large stale attachments found (or Full Disk Access needed)."
            }
        case .spaceLens:
            spaceNodes = await lens.scanHome()
            items = []
        case .browser:
            items = await browser.scan(includeHistory: includeBrowserHistory)
        }
    }

    func toggleItem(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].selected.toggle()
    }

    func selectAllSafe() {
        for i in items.indices {
            if items[i].risk == .safeJunk { items[i].selected = true }
        }
    }

    func cleanSelected() async {
        isCleaning = true
        status = "Cleaning…"
        defer { isCleaning = false }

        var working = items.filter(\.selected)
        var result = CleanRunResult()

        // Special actions first
        for item in working {
            if item.meta["action"] == "purge" {
                let before = MachMemory.sample()?.availableBytes ?? 0
                let purge = await SystemCleaner().purgeInactiveMemory()
                result.memoryPurged = purge.memoryPurged
                result.availableBefore = before
                result.availableAfter = purge.availableAfter
                working.removeAll { $0.id == item.id }
            } else if item.meta["action"] == "brew-cleanup" || item.meta["action"] == "simctl-unavailable" {
                let partial = await dev.runSpecial(item)
                result.freedBytes += partial.freedBytes
                result.itemsProcessed += partial.itemsProcessed
                result.errors.append(contentsOf: partial.errors)
                working.removeAll { $0.id == item.id }
            }
        }

        let applied = CleanExecutor.apply(working)
        result.freedBytes += applied.freedBytes
        result.itemsProcessed += applied.itemsProcessed
        result.errors.append(contentsOf: applied.errors)

        lastResult = result
        status = result.summary
        ActionReportStore.shared.publish(ActionReport(
            title: "Cleaner · \(tab.title)",
            availableBefore: result.availableBefore,
            availableAfter: result.availableAfter,
            bytesCleaned: result.freedBytes,
            detail: result.summary
        ))
        await refresh()
    }

    func selectApp(_ app: InstalledApp) async {
        selectedApp = app
        items = await uninstaller.leftovers(for: app)
    }

    func setStartupEnabled(_ item: StartupItem, enabled: Bool) async {
        if item.kind == .systemAgent {
            status = "System agents are read-only (list only)."
            return
        }
        if item.isApple {
            status = "Apple agents cannot be disabled here."
            return
        }
        let ok = await login.setEnabled(item, enabled: enabled)
        status = ok ? (enabled ? "Enabled \(item.name)" : "Disabled \(item.name)") : "Failed to update \(item.name)"
        startupItems = await login.list()
    }

    func deleteSnapshots(_ selected: [LocalSnapshot]) async {
        isCleaning = true
        defer { isCleaning = false }
        let result = await snaps.deleteAllListed(selected)
        status = "Snapshots removed: \(result.ok), failed: \(result.fail)"
        snapshots = await snaps.list()
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
