import SwiftUI

struct CircularGauge: View {
    let title: String
    let value: Double
    let band: MetricBand
    var centerText: String
    var caption: String? = nil
    var symbol: String = "circle"

    @State private var animated = false

    private var clamped: Double { min(1, max(0, value)) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Soft glow
                Circle()
                    .fill(TurboTheme.bandColor(band).opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.05)

                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 9)

                Circle()
                    .trim(from: 0, to: animated ? clamped : 0)
                    .stroke(
                        AngularGradient(
                            colors: [
                                TurboTheme.bandColor(band).opacity(0.55),
                                TurboTheme.bandColor(band),
                                TurboTheme.bandColor(band).opacity(0.9)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: TurboTheme.bandColor(band).opacity(0.35), radius: 4, y: 1)

                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TurboTheme.bandColor(band))
                        .fgSymbolPulse(isActive: band == .bad)

                    Text(centerText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .fgNumericTextTransition()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 78, height: 78)
            .onAppear {
                withAnimation(MotionTokens.gauge.delay(0.05)) { animated = true }
            }
            .fgOnChange(of: clamped) { _ in
                animated = true
            }

            VStack(spacing: 2) {
                Text(title)
                    .font(Design.Text.caption)
                    .foregroundStyle(.primary)
                if let caption {
                    Text(caption)
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
