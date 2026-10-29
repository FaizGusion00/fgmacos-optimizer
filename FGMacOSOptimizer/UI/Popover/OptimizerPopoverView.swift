import SwiftUI

struct OptimizerPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appearanceStore: AppearanceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    /// Bumps identity so SwiftUI fully refreshes when appearance changes (avoids double-tap lag).
    @State private var appearanceToken = UUID()

    private var theme: TurboTheme { TurboTheme(isActive: appState.isTurboActive) }
    private var primary: Color { TurboTheme.primaryLabel(for: colorScheme) }
    private var secondary: Color { TurboTheme.secondaryLabel(for: colorScheme) }
    private var tertiary: Color { TurboTheme.tertiaryLabel(for: colorScheme) }

    var body: some View {
        ZStack {
            VibrancyBackground(
                material: colorScheme == .light ? .menu : .hudWindow,
                blendingMode: .behindWindow,
                appearance: appearanceStore.appearance
            )

            LinearGradient(
                colors: [
                    theme.accent.opacity(appState.isTurboActive ? (colorScheme == .light ? 0.12 : 0.18) : (colorScheme == .light ? 0.06 : 0.08)),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
            .animation(MotionTokens.panel, value: appState.isTurboActive)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                appearancePicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        sectionCard { StatusGaugesView(metrics: appState.displayMetrics) }
                        sectionCard { ActionButtonsView() }
                        sectionCard { WatchdogListView() }
                        sectionCard { AuthSessionView() }
                        sectionCard { StartupSettingsView() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }

                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .frame(width: Design.popoverWidth, height: Design.popoverHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .id(appearanceToken)
        .preferredColorScheme(appearanceStore.appearance.colorScheme)
        .animation(.easeInOut(duration: 0.22), value: appearanceStore.appearance)
        .onAppear {
            withAnimation(MotionTokens.appearFast) { appeared = true }
        }
        .fgOnChange(of: appearanceStore.appearance) { newValue in
            appearanceToken = UUID()
            NotificationCenter.default.post(name: .fgAppearanceDidChange, object: newValue)
        }
        .alert("Notice", isPresented: Binding(
            get: { appState.actionError != nil },
            set: { if !$0 { appState.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { appState.actionError = nil }
        } message: {
            Text(appState.actionError ?? "")
        }
        .background(PopoverAppearanceApplier(appearance: appearanceStore.appearance))
    }

    private var appearancePicker: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appearanceStore.set(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11, weight: .bold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(appearanceStore.appearance == mode ? Color.white : primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(appearanceStore.appearance == mode ? theme.accent : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(TurboTheme.cardStroke(for: colorScheme), lineWidth: 1)
        )
        .accessibilityLabel("Appearance")
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.radius, style: .continuous)
                    .fill(TurboTheme.cardFill(for: colorScheme))
                    .background(
                        RoundedRectangle(cornerRadius: Design.radius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.radius, style: .continuous)
                            .stroke(TurboTheme.cardStroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .light ? 0.07 : 0.28), radius: 10, y: 3)
            )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.turboGradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: theme.accent.opacity(0.45), radius: 8, y: 2)
                Image(systemName: appState.isTurboActive ? "bolt.fill" : "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .fgSymbolPulse(isActive: appState.isTurboActive)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("FGMacOS Optimizer")
                    .font(Design.Text.title)
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(appState.isTurboActive ? "Turbo Mode · focused" : "System health · live")
                    .font(Design.Text.caption)
                    .foregroundStyle(appState.isTurboActive ? theme.accent : secondary)
            }

            Spacer(minLength: 8)

            Button {
                appState.sampler.kick()
                appState.watchdog.kick()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Refresh metrics now")

            if appState.isOptimizing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                PermissionsWindowController.show()
            } label: {
                Label("Permissions", systemImage: "lock.shield.fill")
                    .font(Design.Text.caption)
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("v1.0.2")
                .font(Design.Text.micro)
                .foregroundStyle(tertiary)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Design.Text.caption)
                    .foregroundStyle(secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Applies NSAppearance to the nearest window — required for reliable Light/Dark in NSPopover.
private struct PopoverAppearanceApplier: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        let ns = appearance.nsAppearance
        view.appearance = ns
        if let window = view.window {
            window.appearance = ns
            window.contentView?.appearance = ns
            window.contentView?.subviews.forEach { $0.appearance = ns }
        }
    }
}
