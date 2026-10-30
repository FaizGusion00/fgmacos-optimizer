import SwiftUI

struct WatchdogListView: View {
    @EnvironmentObject private var appState: AppState

    private var scanAge: Int {
        max(0, Int(Date().timeIntervalSince(appState.watchdogLastScan)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Watchdog", systemImage: "eye.fill")
                    .font(Design.Text.section)
                    .foregroundStyle(.primary.opacity(0.8))
                if appState.watchdogScanning {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Text(scanAge < 5 ? "live" : "\(scanAge)s")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Text("\(appState.watchdogItems.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(appState.watchdogItems.isEmpty ? Color.primary.opacity(0.08) : Color.red.opacity(0.18)))
                    .foregroundStyle(appState.watchdogItems.isEmpty ? .secondary : Color.red)
            }

            // Always-visible top CPU (awareness)
            if !appState.topProcesses.isEmpty {
                VStack(spacing: 4) {
                    ForEach(appState.topProcesses.prefix(3)) { proc in
                        HStack {
                            Text(proc.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", proc.cpuPercent))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(proc.cpuPercent >= 70 ? Color.red : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }

            if appState.watchdogItems.isEmpty {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(TurboTheme.bandColor(.good).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TurboTheme.bandColor(.good))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All clear")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("No killable hogs · scanning live")
                            .font(Design.Text.caption)
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                    Spacer()
                }
                .padding(10)
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.watchdogItems.prefix(5)) { item in
                        WatchdogRow(item: item) {
                            appState.killItem(item)
                        }
                    }
                }
            }
        }
    }
}

private struct WatchdogRow: View {
    let item: WatchdogItem
    let onKill: () -> Void
    @State private var hover = false

    private var icon: String {
        switch item.kind {
        case .hung: return "exclamationmark.triangle.fill"
        case .hog: return "flame.fill"
        case .elevated: return "gauge.with.dots.needle.67percent"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .hung: return .orange
        case .hog: return .red
        case .elevated: return Color(red: 0.95, green: 0.55, blue: 0.1)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(item.detail)
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onKill) {
                Text("Kill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .help("Force quit")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(hover ? 0.12 : 0.07))
        )
        .onHover { hover = $0 }
    }
}
