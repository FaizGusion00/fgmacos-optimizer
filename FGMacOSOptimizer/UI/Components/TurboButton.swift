import SwiftUI

struct TurboButton: View {
    let isActive: Bool
    let isBusy: Bool
    let action: () -> Void

    @State private var pressed = false
    @State private var hover = false
    @State private var showParticles = false

    private var theme: TurboTheme { TurboTheme(isActive: isActive) }

    var body: some View {
        Button {
            runPress()
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Design.radiusSm, style: .continuous)
                    .fill(theme.turboGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.radiusSm, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: theme.accent.opacity(isActive || hover ? 0.45 : 0.2), radius: isActive ? 16 : 8, y: 4)

                if showParticles {
                    ParticleRing(color: .white).allowsHitTesting(false)
                }

                HStack(spacing: 10) {
                    Image(systemName: isActive ? "bolt.fill" : "gauge.with.needle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .symbolEffect(.bounce, value: pressed)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isActive ? "Turbo On" : "Boost Now")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(isActive
                               ? "Indexing off · search still works"
                               : "Pause Spotlight indexing (not search)")
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.85)
                    }

                    Spacer(minLength: 0)

                    if isBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
            }
            .frame(height: 56)
            .scaleEffect(pressed ? 0.97 : (hover ? 1.015 : 1.0))
            .animation(MotionTokens.turbo, value: pressed)
            .animation(MotionTokens.panel, value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onChange(of: isActive) { _, active in
            if active { burst() }
        }
    }

    private func runPress() {
        pressed = true
        burst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
    }

    private func burst() {
        showParticles = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { showParticles = false }
    }
}

private struct ParticleRing: View {
    let color: Color
    @State private var expand = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let t = expand ? 1.0 : 0.0
            for i in 0..<14 {
                let angle = (Double(i) / 14.0) * .pi * 2
                let radius = 12 + t * 36
                let x = center.x + CGFloat(cos(angle)) * radius
                let y = center.y + CGFloat(sin(angle)) * radius
                let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                context.opacity = 1 - t
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { expand = true }
        }
    }
}
