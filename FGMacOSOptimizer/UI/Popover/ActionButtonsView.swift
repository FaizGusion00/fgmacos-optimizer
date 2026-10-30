import SwiftUI

struct ActionButtonsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var heroHover = false
    @State private var heroPress = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            // Hero: the one button a tired human should press.
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    heroPress = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    heroPress = false
                    appState.speedBoost()
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hare.fill")
                            .font(.system(size: 16, weight: .bold))
                            .symbolEffectBounce(value: appeared)
                        Text("Quick Optimize")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        Text("1 tap")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    Text("Clear safe caches & old logs · pause backup · calm Spotlight · free RAM. Admin once.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.95)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.58, blue: 0.42),
                                    Color(red: 0.10, green: 0.42, blue: 0.58)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.10, green: 0.50, blue: 0.45).opacity(heroHover ? 0.45 : 0.28), radius: heroHover ? 16 : 10, y: heroHover ? 8 : 5)
                )
                .scaleEffect(heroPress ? 0.97 : (heroHover ? 1.015 : 1.0))
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: heroHover)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: heroPress)
            }
            .buttonStyle(.plain)
            .disabled(appState.isOptimizing)
            .opacity(appState.isOptimizing ? 0.55 : 1)
            .onHover { heroHover = $0 }
            .help("One-shot tune-up. Different from Turbo Mode (which stays on).")
            .accessibilityLabel("Quick Optimize. Clears safe caches and old logs, pauses backup, keeps heavy folders out of Spotlight, frees RAM.")
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            if let report = appState.lastReport {
                ActionReportBanner(report: report)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TurboButton(
                isActive: appState.isTurboActive,
                isBusy: appState.isOptimizing
            ) {
                appState.toggleTurbo()
            }
            .disabled(appState.isOptimizing)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            if let msg = appState.turboProgress {
                Text(msg)
                    .font(Design.Text.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .disabled(appState.isOptimizing)
            .opacity(appState.isOptimizing ? 0.55 : 1)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)

            // Secondary: deep space reclaim with review-and-confirm.
            Button {
                CleanerWindowController.show(showIntroIfNeeded: true)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CleanerTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Cleaner")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Review & free more space — Smart Care, large files, uninstall")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CleanerTheme.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CleanerTheme.accent.opacity(0.30), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isOptimizing)
            .opacity(appState.isOptimizing ? 0.55 : 1)
            .help("Cleaner suite — Smart Care and all cleanup tools")
            .accessibilityLabel("Open Cleaner. Opens the Cleaner suite window.")
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
