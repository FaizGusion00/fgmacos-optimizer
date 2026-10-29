import SwiftUI

struct CleanerRootView: View {
    @EnvironmentObject private var store: CleanerStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            VStack(spacing: 0) {
                header
                detailBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footerBar
            }
            .background(detailBackground)
        }
        .frame(minWidth: 780, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.04), Color.clear]
                : [CleanerTheme.mist.opacity(0.9), Color.white.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CleanerTheme.heroGradient)
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cleaner")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("FGMacOS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(CleanCategory.allCases) { cat in
                        sidebarRow(cat)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .background(
            colorScheme == .dark
                ? Color.white.opacity(0.04)
                : Color(red: 0.94, green: 0.93, blue: 0.91)
        )
    }

    private func sidebarRow(_ cat: CleanCategory) -> some View {
        let active = store.tab == cat
        return Button {
            store.selectTab(cat)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cat.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(active ? Color.white : CleanerTheme.accent)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(active ? Color.white.opacity(0.22) : CleanerTheme.accent.opacity(0.12))
                    )
                Text(cat.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(active ? Color.white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(sidebarRowBackground(active: active))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarRowBackground(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CleanerTheme.heroGradient)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clear)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.tab.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(headerBlurb)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)

            if store.selectedBytes > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Selected")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(CleanSafety.formatBytes(store.selectedBytes))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CleanerTheme.accentDeep)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CleanerTheme.accent.opacity(0.12))
                )
            }

            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.isScanning ? "Scanning…" : "Scan", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(store.isScanning || store.isCleaning)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var headerBlurb: String {
        switch store.tab {
        case .smartCare: return "One-tap cleanup · safe junk selected by default"
        case .uninstaller: return "Remove apps and leftovers · Apple apps hidden"
        case .largeOld: return "Files over 100 MB or older than 30 days"
        case .duplicates: return "Opt-in hash scan in Downloads"
        case .loginItems: return "Disable user LaunchAgents · reversible"
        case .snapshots: return "Local Time Machine snapshots only"
        case .dev: return "Xcode, simulators, npm, pip, Homebrew"
        case .mailMessages: return "Large stale attachments → Trash"
        case .spaceLens: return "Where disk space went"
        case .browser: return "Caches only by default · never cookies"
        }
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
            VStack(alignment: .leading, spacing: 0) {
                tipBanner(
                    title: "Duplicates stay off until you enable them",
                    detail: "Scans ~/Downloads with size + hash matching. Slow is normal."
                ) {
                    Toggle("Enable scan", isOn: $store.duplicatesEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fgOnChange(of: store.duplicatesEnabled) { enabled in
                            if enabled { Task { await store.refresh() } }
                        }
                }
                CleanItemsListView()
            }
        case .browser:
            VStack(alignment: .leading, spacing: 0) {
                tipBanner(
                    title: "Cookies & passwords are never touched",
                    detail: "Quit the browser first if clean fails on locked files."
                ) {
                    Toggle("Include history", isOn: $store.includeBrowserHistory)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fgOnChange(of: store.includeBrowserHistory) { _ in
                            Task { await store.refresh() }
                        }
                }
                CleanItemsListView()
            }
        default:
            CleanItemsListView()
        }
    }

    private func tipBanner<Trailing: View>(
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(CleanerTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanerTheme.accent.opacity(0.08))
                .padding(.horizontal, 14)
                .padding(.top, 8)
        )
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            if !store.items.isEmpty {
                Button("Select safe") { store.selectAllSafe() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let status = store.status, store.isScanning || store.isCleaning {
                ProgressView().controlSize(.mini)
                Text(status)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let result = store.lastResult {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(TurboTheme.bandColor(.good))
                Text(result.summary)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(TurboTheme.bandColor(.good))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await store.cleanSelected() }
            } label: {
                HStack(spacing: 6) {
                    if store.isCleaning {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                    Text(store.isCleaning ? "Cleaning…" : "Clean selected")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(store.items.contains(where: \.selected)
                              ? CleanerTheme.heroGradient
                              : LinearGradient(colors: [Color.gray.opacity(0.45), Color.gray.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isCleaning || !store.items.contains(where: \.selected))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct CleanItemsListView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.items.isEmpty {
            CleanerEmptyState(
                symbol: store.isScanning ? "hourglass" : "tray",
                title: store.isScanning ? "Scanning…" : "Nothing to clean here",
                detail: store.status ?? "Tap Scan — or pick another category."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.items) { item in
                        CleanItemCard(item: item) {
                            store.toggleItem(item.id)
                        } reveal: {
                            if let path = item.paths.first {
                                store.reveal(path)
                            }
                        }
                        .disabled(store.isCleaning)
                    }
                }
                .padding(14)
            }
        }
    }
}

struct CleanItemCard: View {
    let item: CleanItem
    let toggle: () -> Void
    let reveal: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.selected ? CleanerTheme.accent : Color.secondary.opacity(0.45))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        riskChip
                    }
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if item.bytes > 0 {
                    Text(CleanSafety.formatBytes(item.bytes))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.8))
                }
                Button(action: reveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(item.selected ? CleanerTheme.accent.opacity(0.10) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(item.selected ? CleanerTheme.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var riskChip: some View {
        Text(CleanerTheme.riskLabel(item.risk))
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(CleanerTheme.riskColor(item.risk))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(CleanerTheme.riskColor(item.risk).opacity(0.14))
            )
    }
}

struct CleanerEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(CleanerTheme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CleanerTheme.accent)
            }
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
