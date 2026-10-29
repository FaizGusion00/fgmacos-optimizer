import SwiftUI

struct UninstallerTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        HStack(spacing: 0) {
            appListColumn
                .frame(width: 230)
                .background(Color.primary.opacity(0.03))
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            leftoversColumn
                .frame(maxWidth: .infinity)
        }
    }

    private var appListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Apps")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if store.installedApps.isEmpty {
                CleanerEmptyState(
                    symbol: "app.badge.checkmark",
                    title: store.isScanning ? "Scanning apps…" : "No removable apps",
                    detail: "Apple system apps stay hidden."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.installedApps) { app in
                            appRow(app)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let active = store.selectedApp?.id == app.id
        return Button {
            Task { await store.selectApp(app) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "app.fill")
                    .foregroundStyle(active ? Color.white : CleanerTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .lineLimit(1)
                    Text(CleanSafety.formatBytes(app.bytes))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(active ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(appRowBackground(active: active))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func appRowBackground(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CleanerTheme.heroGradient)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private var leftoversColumn: some View {
        Group {
            if store.selectedApp == nil {
                CleanerEmptyState(
                    symbol: "hand.tap",
                    title: "Pick an app",
                    detail: "We'll list leftovers: prefs, caches, support files."
                )
            } else {
                CleanItemsListView()
            }
        }
    }
}

struct StartupTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.startupItems.isEmpty {
            CleanerEmptyState(
                symbol: "bolt.horizontal.circle",
                title: store.isScanning ? "Scanning startup…" : "No LaunchAgents found",
                detail: "User agents can be disabled; Apple/system stay read-only."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.startupItems) { item in
                        startupRow(item)
                    }
                }
                .padding(14)
            }
        }
    }

    private func startupRow(_ item: StartupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.enabled ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(item.enabled ? CleanerTheme.accent : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("\(item.kind.rawValue) · \(item.path)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            startupTrailing(item)
            Button { store.reveal(item.path) } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .bold))
                    .padding(6)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private func startupTrailing(_ item: StartupItem) -> some View {
        if item.kind == .systemAgent || item.isApple {
            Text(item.isApple ? "Apple" : "System")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        } else {
            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { newValue in
                    Task { await store.setStartupEnabled(item, enabled: newValue) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}

struct SnapshotsTabView: View {
    @EnvironmentObject private var store: CleanerStore
    @State private var selected = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            snapshotTip
            if store.snapshots.isEmpty {
                CleanerEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: store.isScanning ? "Checking snapshots…" : "No local snapshots",
                    detail: "Nothing to thin right now."
                )
            } else {
                snapshotList
                snapshotActions
            }
        }
    }

    private var snapshotTip: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(CleanerTheme.accent)
            Text("Local APFS snapshots only — external Time Machine backups are untouched.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CleanerTheme.accent.opacity(0.08))
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var snapshotList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.snapshots) { snap in
                    snapshotRow(snap)
                }
            }
            .padding(14)
        }
    }

    private func snapshotRow(_ snap: LocalSnapshot) -> some View {
        let on = selected.contains(snap.id)
        return Button {
            if on { selected.remove(snap.id) } else { selected.insert(snap.id) }
        } label: {
            HStack {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? CleanerTheme.accent : Color.secondary)
                Text(snap.dateString)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? CleanerTheme.accent.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private var snapshotActions: some View {
        HStack {
            Button("Thin selected") {
                let picks = store.snapshots.filter { selected.contains($0.id) }
                Task { await store.deleteSnapshots(picks) }
            }
            .buttonStyle(.borderedProminent)
            .tint(CleanerTheme.accent)
            .disabled(selected.isEmpty || store.isCleaning)

            Button("Thin all listed") {
                Task { await store.deleteSnapshots(store.snapshots) }
            }
            .buttonStyle(.bordered)
            .disabled(store.snapshots.isEmpty || store.isCleaning)
            Spacer()
        }
        .padding(14)
    }
}

struct SpaceLensTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.spaceNodes.isEmpty {
            CleanerEmptyState(
                symbol: "chart.pie",
                title: store.isScanning ? "Mapping disk…" : "No map yet",
                detail: "Tap Scan to size Home and Applications."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.spaceNodes) { node in
                        spaceSection(node)
                    }
                }
                .padding(14)
            }
        }
    }

    private func spaceSection(_ node: SpaceNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(node.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text(CleanSafety.formatBytes(node.bytes))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(CleanerTheme.accentDeep)
            }
            ForEach(node.children.prefix(24)) { child in
                spaceRow(child, parentBytes: max(node.bytes, 1))
                ForEach(child.children.prefix(6)) { grand in
                    spaceRow(grand, parentBytes: max(child.bytes, 1), indent: true)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func spaceRow(_ node: SpaceNode, parentBytes: UInt64, indent: Bool = false) -> some View {
        let ratio = min(1, Double(node.bytes) / Double(max(parentBytes, 1)))
        return HStack(spacing: 10) {
            Text(node.name)
                .font(.system(size: indent ? 11 : 12, weight: .semibold, design: .rounded))
                .padding(.leading, indent ? 14 : 0)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(CleanerTheme.heroGradient)
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
            Text(CleanSafety.formatBytes(node.bytes))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
            Button { store.reveal(node.path) } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
    }
}
