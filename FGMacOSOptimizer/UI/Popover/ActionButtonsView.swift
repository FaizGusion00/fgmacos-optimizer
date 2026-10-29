import SwiftUI

struct ActionButtonsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var heroHover = false
    @State private var heroPress = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    heroPress = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    heroPress = false
                    CleanerWindowController.show(showIntroIfNeeded: true)
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .symbolEffectBounce(value: appeared)
                        Text("Open Cleaner")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        Text("Suite")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    Text("Scan · review · free space. Uninstall apps, large files, Dev caches, and more.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.95)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CleanerTheme.heroGradient)
                        .shadow(color: CleanerTheme.accent.opacity(heroHover ? 0.45 : 0.28), radius: heroHover ? 16 : 10, y: heroHover ? 8 : 5)
                )
                .scaleEffect(heroPress ? 0.97 : (heroHover ? 1.015 : 1.0))
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: heroHover)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: heroPress)
            }
            .buttonStyle(.plain)
            .onHover { heroHover = $0 }
            .accessibilityLabel("Open Cleaner. Opens the Cleaner suite window.")
            .help("Cleaner suite — Smart Care and all cleanup tools")
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            TurboButton(
                isActive: appState.isTurboActive,
                isBusy: appState.isOptimizing && appState.turboProgress != nil
            ) {
                appState.toggleTurbo()
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            if let msg = appState.turboProgress {
                Text(msg)
                    .font(Design.Text.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let report = appState.lastReport {
                ActionReportBanner(report: report)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 8) {
                ActionChip(title: "Free RAM", symbol: "arrow.3.trianglepath", tint: Color(red: 0.35, green: 0.55, blue: 1.0)) {
                    appState.freeRAM()
                }
                ActionChip(title: "Deep Clean", symbol: "trash.fill", tint: Color.orange.opacity(0.9)) {
                    appState.clearCache()
                }
                ActionChip(title: "Kill Hogs", symbol: "xmark.octagon.fill", tint: Color.red) {
                    appState.killHogs()
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: appeared)
        .animation(.easeInOut(duration: 0.25), value: appState.turboProgress)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84).delay(0.05)) {
                appeared = true
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
                    .fill(tint.opacity(hover ? 0.18 : 0.10))
            )
            .scaleEffect(hover ? 1.03 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hover)
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
