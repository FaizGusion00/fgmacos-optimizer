import SwiftUI

/// One urgent condition at a time (disk → memory → heat) with a single obvious action.
/// Reads only `displayMetrics` (published while the popover is open). No timers, no loops.
struct UrgentBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if !appState.isOptimizing,
           Date() >= appState.urgentSnoozedUntil,
           let condition = appState.displayMetrics.urgentCondition {
            HStack(spacing: 10) {
                Image(systemName: symbol(condition))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TurboTheme.bandColor(.bad))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(condition))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text(detail(condition))
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(actionTitle(condition)) {
                    appState.urgentSnoozedUntil = Date().addingTimeInterval(600)
                    act(condition)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(TurboTheme.bandColor(.bad))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TurboTheme.bandColor(.bad).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TurboTheme.bandColor(.bad).opacity(0.28), lineWidth: 1)
                    )
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private func symbol(_ c: UrgentCondition) -> String {
        switch c {
        case .disk: return "internaldrive.fill"
        case .memory: return "memorychip.fill"
        case .thermal: return "thermometer.high"
        }
    }

    private func title(_ c: UrgentCondition) -> String {
        switch c {
        case .disk(let free): return "Disk almost full · \(SystemMetrics.formatGB(free)) free"
        case .memory: return "Memory pressure critical"
        case .thermal(let level): return "Mac is running \(level == .critical ? "very hot" : "hot")"
        }
    }

    private func detail(_ c: UrgentCondition) -> String {
        switch c {
        case .disk: return "Low space slows everything. Clear safe caches and old logs now."
        case .memory: return "Apps are swapping to disk. Free reclaimable RAM (admin once)."
        case .thermal: return "Quit CPU hogs and lower power so the fans can catch up."
        }
    }

    private func actionTitle(_ c: UrgentCondition) -> String {
        switch c {
        case .disk: return "Quick Optimize"
        case .memory: return "Free RAM"
        case .thermal: return "Cool down"
        }
    }

    private func act(_ c: UrgentCondition) {
        switch c {
        case .disk: appState.speedBoost()
        case .memory: appState.freeRAM()
        case .thermal: appState.coolDown()
        }
    }
}
