import SwiftUI

struct UninstallerTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        HSplitView {
            List(store.installedApps, selection: Binding(
                get: { store.selectedApp?.id },
                set: { id in
                    guard let id, let app = store.installedApps.first(where: { $0.id == id }) else { return }
                    Task { await store.selectApp(app) }
                }
            )) { app in
                HStack {
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    Text(CleanSafety.formatBytes(app.bytes))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .tag(app.id)
            }
            .frame(minWidth: 200, idealWidth: 240)

            CleanItemsListView()
        }
    }
}

struct StartupTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.startupItems.isEmpty {
            empty("No LaunchAgents found", "Scan to refresh user and system agents.")
        } else {
            List(store.startupItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("\(item.kind.rawValue) · \(item.path)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if item.kind == .systemAgent || item.isApple {
                        Text(item.isApple ? "Apple" : "System")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
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
                    Button {
                        store.reveal(item.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listStyle(.inset)
        }
    }
}

struct SnapshotsTabView: View {
    @EnvironmentObject private var store: CleanerStore
    @State private var selected = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Time Machine snapshots only. Backups on external disks are not touched.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            if store.snapshots.isEmpty {
                empty("No local snapshots", "Your Mac may have none right now.")
            } else {
                List(store.snapshots, selection: $selected) { snap in
                    Text(snap.dateString)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .tag(snap.id)
                }
                .listStyle(.inset)

                HStack {
                    Button("Thin selected") {
                        let picks = store.snapshots.filter { selected.contains($0.id) }
                        Task { await store.deleteSnapshots(picks) }
                    }
                    .disabled(selected.isEmpty || store.isCleaning)
                    Button("Thin all listed") {
                        Task { await store.deleteSnapshots(store.snapshots) }
                    }
                    .disabled(store.snapshots.isEmpty || store.isCleaning)
                    Spacer()
                }
                .padding(12)
            }
        }
    }
}

struct SpaceLensTabView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.spaceNodes.isEmpty {
            empty("No data", "Tap Scan to map Home and Applications.")
        } else {
            List {
                ForEach(store.spaceNodes) { node in
                    Section(header: HStack {
                        Text(node.name)
                        Spacer()
                        Text(CleanSafety.formatBytes(node.bytes))
                            .monospacedDigit()
                    }) {
                        ForEach(node.children.prefix(30)) { child in
                            spaceRow(child)
                            ForEach(child.children.prefix(8)) { grand in
                                spaceRow(grand, indent: true)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func spaceRow(_ node: SpaceNode, indent: Bool = false) -> some View {
        HStack {
            Text(node.name)
                .padding(.leading, indent ? 12 : 0)
                .lineLimit(1)
            Spacer()
            GeometryReader { geo in
                let parent = store.spaceNodes.first?.bytes ?? max(node.bytes, 1)
                let ratio = min(1, Double(node.bytes) / Double(max(parent, 1)))
                RoundedRectangle(cornerRadius: 3)
                    .fill(TurboTheme.bandColor(.warn).opacity(0.35))
                    .frame(width: max(4, geo.size.width * ratio), height: 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 120, height: 10)
            Text(CleanSafety.formatBytes(node.bytes))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
            Button {
                store.reveal(node.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
    }
}

@ViewBuilder
private func empty(_ title: String, _ detail: String) -> some View {
    VStack(spacing: 8) {
        Spacer()
        Image(systemName: "tray")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        Text(detail)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
