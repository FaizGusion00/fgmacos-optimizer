import SwiftUI

struct CleanerRootView: View {
    @EnvironmentObject private var store: CleanerStore
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        NavigationSplitView {
            List(CleanCategory.allCases, selection: Binding(
                get: { store.tab },
                set: { store.selectTab($0) }
            )) { cat in
                Label(cat.title, systemImage: cat.symbol)
                    .tag(cat)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                detailBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.tab.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if let status = store.status {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if store.isScanning || store.isCleaning {
                ProgressView().controlSize(.small)
            }
            Button("Scan") {
                Task { await store.refresh() }
            }
            .disabled(store.isScanning || store.isCleaning)
        }
        .padding(14)
    }

    @ViewBuilder
    private var detailBody: some View {
        switch store.tab {
        case .loginItems:
            StartupTabView()
        case .snapshots:
            SnapshotsTabView()
        case .spaceLens:
            SpaceLensTabView()
        case .uninstaller:
            UninstallerTabView()
        case .duplicates:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable duplicate scan (Downloads, slow)", isOn: $store.duplicatesEnabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .fgOnChange(of: store.duplicatesEnabled) { enabled in
                        if enabled { Task { await store.refresh() } }
                    }
                CleanItemsListView()
            }
        case .browser:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Include browser history (off = cache only)", isOn: $store.includeBrowserHistory)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .fgOnChange(of: store.includeBrowserHistory) { _ in
                        Task { await store.refresh() }
                    }
                Text("Never removes Cookies or passwords.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                CleanItemsListView()
            }
        default:
            CleanItemsListView()
        }
    }

    private var footer: some View {
        HStack {
            if !store.items.isEmpty {
                Button("Select safe") { store.selectAllSafe() }
                    .controlSize(.small)
                Text("\(CleanSafety.formatBytes(store.selectedBytes)) selected")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let result = store.lastResult {
                Text(result.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(TurboTheme.bandColor(.good))
                    .lineLimit(1)
            }
            Button("Clean selected") {
                Task { await store.cleanSelected() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.isCleaning || store.items.filter(\.selected).isEmpty)
        }
        .padding(12)
    }
}

struct CleanItemsListView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.items.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(store.isScanning ? "Scanning…" : "Nothing found")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(store.status ?? "Tap Scan to refresh.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { item.selected },
                            set: { _ in store.toggleItem(item.id) }
                        ))
                        .labelsHidden()
                        .disabled(store.isCleaning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if item.bytes > 0 {
                            Text(CleanSafety.formatBytes(item.bytes))
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                        if let path = item.paths.first {
                            Button {
                                store.reveal(path)
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
        }
    }
}
