import SwiftUI

struct ActionButtonsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            TurboButton(
                isActive: appState.isTurboActive,
                isBusy: appState.isOptimizing && appState.turboProgress != nil
            ) {
                appState.toggleTurbo()
            }

            HStack(spacing: 6) {
                Image(systemName: appState.turbo.indexingDisabledVerified ? "checkmark.seal.fill" : "questionmark.circle")
                    .foregroundStyle(appState.turbo.indexingDisabledVerified ? TurboTheme.bandColor(.good) : .secondary)
                    .font(.system(size: 11, weight: .bold))
                Text(appState.turbo.lastVerifiedDetail)
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if let msg = appState.turboProgress {
                Text(msg)
                    .font(Design.Text.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let report = appState.lastReport {
                ActionReportBanner(report: report)
            }

            HStack(spacing: 10) {
                ActionChip(title: "Free RAM", symbol: "arrow.3.trianglepath", tint: Color(red: 0.35, green: 0.55, blue: 1.0)) {
                    appState.freeRAM()
                }
                ActionChip(title: "Cleaner", symbol: "sparkles", tint: Color.orange) {
                    CleanerWindowController.show()
                }
                ActionChip(title: "Kill Hogs", symbol: "xmark.octagon.fill", tint: Color.red) {
                    appState.killHogs()
                }
            }
        }
    }
}

private struct ActionChip: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    @State private var bounced = false
    @State private var hover = false

    var body: some View {
        Button {
            bounced.toggle()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffectBounce(value: bounced)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(hover ? 0.16 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private extension View {
    @ViewBuilder
    func symbolEffectBounce(value: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
