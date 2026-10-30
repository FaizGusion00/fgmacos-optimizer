import SwiftUI

struct ScheduleTabView: View {
    @ObservedObject private var scheduler = SmartCareScheduler.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tip(
                    title: "Scan only — never auto-clean",
                    detail: "When due, Smart Care scans and notifies how much you can free. You confirm in Cleaner before anything is removed. Scheduled scans need “Keep in menu bar” (Startup section in the menu)."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Frequency")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Frequency", selection: $scheduler.frequency) {
                        ForEach(SmartCareScheduleFrequency.allCases) { freq in
                            Text(freq.title).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fgOnChange(of: scheduler.frequency) { _ in
                        scheduler.start()
                    }

                    Text(scheduler.nextDueDescription)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(cardBG)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last scheduled scan")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let last = scheduler.lastScanAt {
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(scheduler.lastFoundBytes > 0
                             ? "Found \(CleanSafety.formatBytes(scheduler.lastFoundBytes)) · \(scheduler.lastItemCount) items"
                             : "No significant junk found")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not run yet")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    if let status = scheduler.status {
                        Text(status)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CleanerTheme.accent)
                    }
                }
                .padding(14)
                .background(cardBG)

                HStack(spacing: 10) {
                    Button {
                        Task { await scheduler.runNow() }
                    } label: {
                        Label(scheduler.isScanning ? "Scanning…" : "Scan now & notify", systemImage: "bell.badge")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(CleanerTheme.heroGradient))
                    }
                    .buttonStyle(.plain)
                    .disabled(scheduler.isScanning)

                    Button("Open Smart Care") {
                        scheduler.openCleanerForReview()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
        }
    }

    private var cardBG: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04))
    }

    private func tip(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CleanerTheme.accent)
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanerTheme.accent.opacity(0.10))
        )
    }
}

struct ProtectionTabView: View {
    @ObservedObject private var protection = ProtectionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tipBanner
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Protected folders", actionTitle: "Add folder") {
                        protection.pickFolder()
                    }
                    if protection.paths.isEmpty {
                        emptyLine("No folders yet — add Desktop projects, photo libraries, etc.")
                    } else {
                        ForEach(protection.paths, id: \.self) { path in
                            row(path) { protection.removePath(path) }
                        }
                    }

                    sectionHeader("Protected apps", actionTitle: "Add app") {
                        protection.pickApp()
                    }
                    if protection.bundleIDs.isEmpty {
                        emptyLine("No apps yet — hidden from Uninstaller targeting.")
                    } else {
                        ForEach(protection.bundleIDs, id: \.self) { bid in
                            row(bid) { protection.removeBundleID(bid) }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private var tipBanner: some View {
        Text("Protected paths are skipped by every scanner and blocked from Clean. Your own apps can be added so leftovers never appear.")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CleanerTheme.accent.opacity(0.08))
    }

    private func sectionHeader(_ title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(CleanerTheme.accent)
                .controlSize(.small)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }

    private func row(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(CleanerTheme.accent)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(2)
            Spacer()
            Button("Remove", action: remove)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct HistoryTabView: View {
    @ObservedObject private var history = CleanupHistoryStore.shared
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Undo restores from Trash when the item is still there. Permanent deletes cannot be undone.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !history.batches.isEmpty {
                    Button("Clear log") { history.clearAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(14)
            .background(CleanerTheme.accent.opacity(0.08))

            if let status {
                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CleanerTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            if history.batches.isEmpty {
                CleanerEmptyState(
                    symbol: "arrow.uturn.backward.circle",
                    title: "No cleanups yet",
                    detail: "After you Clean selected items, runs appear here with Undo when possible."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(history.batches) { batch in
                            batchCard(batch)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func batchCard(_ batch: CleanupHistoryBatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.summary)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(batch.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if batch.freedBytes > 0 {
                    Text(CleanSafety.formatBytes(batch.freedBytes))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(CleanerTheme.accentDeep)
                }
            }

            ForEach(batch.entries.prefix(40)) { entry in
                entryRow(entry)
            }
            if batch.entries.count > 40 {
                Text("+\(batch.entries.count - 40) more paths")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func entryRow(_ entry: CleanupHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.restored ? "checkmark.circle.fill" : (entry.canRestore ? "trash" : "trash.slash"))
                .foregroundStyle(entry.restored ? TurboTheme.bandColor(.good) : CleanerTheme.accent)
                .font(.system(size: 12, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(entry.originalPath)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if entry.canRestore {
                Button("Undo") {
                    status = history.restore(entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(CleanerTheme.accent)
                .controlSize(.mini)
            } else if entry.disposal == CleanDisposal.trash.rawValue, !entry.restored {
                Button("Show") { history.revealInTrash(entry) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else if entry.restored {
                Text("Restored")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(TurboTheme.bandColor(.good))
            } else {
                Text("Permanent")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
