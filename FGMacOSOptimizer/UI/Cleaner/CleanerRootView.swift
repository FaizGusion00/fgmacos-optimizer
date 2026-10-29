import SwiftUI

struct CleanerRootView: View {
    @EnvironmentObject private var store: CleanerStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -12)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            VStack(spacing: 0) {
                if store.showGuideBanner {
                    guideBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                header
                if store.tab == .smartCare {
                    smartCareSteps
                        .transition(.opacity)
                }
                detailBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(store.tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
                footerBar
            }
            .background(detailBackground)
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 10)
        }
        .frame(minWidth: 800, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.tab)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: store.showGuideBanner)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var guideBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CleanerTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("You’re in Cleaner — here’s the simple flow")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("1) Stay on Smart Care  ·  2) Wait for Scan  ·  3) Review ticks  ·  4) Press Clean selected. Other tools are in the left menu.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Got it") { store.dismissGuide() }
                .buttonStyle(.borderedProminent)
                .tint(CleanerTheme.accent)
                .controlSize(.small)
        }
        .padding(12)
        .background(CleanerTheme.accent.opacity(0.12))
    }

    private var smartCareSteps: some View {
        HStack(spacing: 8) {
            stepPill(1, "Scan", active: store.smartCareStep == 1 || store.items.isEmpty)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            stepPill(2, "Review", active: store.smartCareStep >= 2 && !store.items.isEmpty)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            stepPill(3, "Clean", active: store.isCleaning || (store.lastResult != nil))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func stepPill(_ n: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(active ? Color.white : .secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(active ? CleanerTheme.accent : Color.primary.opacity(0.08)))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(active ? CleanerTheme.accentDeep : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(active ? CleanerTheme.accent.opacity(0.12) : Color.clear)
        )
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
                        if cat == .schedule {
                            Text("MANAGE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        sidebarRow(cat)
                        if cat == .smartCare {
                            Text("START HERE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(CleanerTheme.accent)
                                .padding(.leading, 12)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                store.selectTab(cat)
            }
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? Color.white : .primary)
                    Text(sidebarHint(cat))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(active ? Color.white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(sidebarRowBackground(active: active))
            .accessibilityLabel("\(cat.title). \(sidebarHint(cat))")
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: active)
    }

    private func sidebarHint(_ cat: CleanCategory) -> String {
        switch cat {
        case .smartCare: return "Recommended · one tap"
        case .uninstaller: return "Remove apps + leftovers"
        case .largeOld: return "Big / old files"
        case .duplicates: return "Same files twice"
        case .loginItems: return "Startup items"
        case .snapshots: return "Hidden TM space"
        case .dev: return "Xcode / npm / brew"
        case .mailMessages: return "Big attachments"
        case .spaceLens: return "What’s using disk"
        case .browser: return "Browser caches"
        case .schedule: return "Auto scan · notify"
        case .protection: return "Never clean these"
        case .history: return "Log + Undo"
        }
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

            if showsScanButton {
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var showsScanButton: Bool {
        switch store.tab {
        case .schedule, .protection, .history: return false
        default: return true
        }
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
        case .schedule: return "Daily/weekly Smart Care scan · notify only, you confirm clean"
        case .protection: return "Whitelist folders and apps so they never get cleaned"
        case .history: return "What was removed · Undo from Trash when still available"
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
        case .schedule:
            ScheduleTabView()
        case .protection:
            ProtectionTabView()
        case .history:
            HistoryTabView()
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
        Group {
            if showsScanButton {
                footerCleanBar
            }
        }
    }

    private var footerCleanBar: some View {
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
                    Text(cleanButtonTitle)
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
            .accessibilityLabel("Clean selected items")
            .help("Removes only the items you checked")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var cleanButtonTitle: String {
        if store.isCleaning { return "Cleaning…" }
        let n = store.items.filter(\.selected).count
        if n == 0 { return "Select items to clean" }
        return "Clean \(n) selected · \(CleanSafety.formatBytes(store.selectedBytes))"
    }
}

struct CleanItemsListView: View {
    @EnvironmentObject private var store: CleanerStore

    var body: some View {
        if store.items.isEmpty {
            VStack(spacing: 14) {
                CleanerEmptyState(
                    symbol: store.isScanning ? "hourglass" : "sparkles",
                    title: store.isScanning ? "Scanning your Mac…" : (store.tab == .smartCare ? "Ready to clean" : "Nothing here yet"),
                    detail: store.status ?? (store.tab == .smartCare
                        ? "Press Scan — we’ll list safe junk you can remove."
                        : "Tap Scan in the header, or choose another tool on the left.")
                )
                if !store.isScanning {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Text(store.tab == .smartCare ? "Scan my Mac" : "Scan this category")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(CleanerTheme.heroGradient))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                }
            }
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
