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

            HStack(spacing: 10) {
                ActionChip(title: "Free RAM", symbol: "arrow.3.trianglepath", tint: Color(red: 0.35, green: 0.55, blue: 1.0)) {
                    appState.freeRAM()
                }
                ActionChip(title: "Clean", symbol: "trash.fill", tint: Color.orange) {
                    appState.clearCache()
                }
                ActionChip(title: "Kill Hogs", symbol: "xmark.octagon.fill", tint: Color.red) {
                    appState.killHogs()
                }
            }

            if let result = appState.lastCleanResult {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(TurboTheme.bandColor(.good))
                    Text(result.summary)
                        .font(Design.Text.caption)
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TurboTheme.bandColor(.good).opacity(0.1))
                )
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
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: bounced)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Design.radiusSm, style: .continuous)
                    .fill(tint.opacity(hover ? 0.22 : 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.radiusSm, style: .continuous)
                            .stroke(tint.opacity(0.25), lineWidth: 1)
                    )
            )
            .foregroundStyle(tint)
            .scaleEffect(hover ? 1.03 : 1.0)
            .animation(MotionTokens.panel, value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
