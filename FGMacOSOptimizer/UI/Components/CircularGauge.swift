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
                Circle()
                    .fill(TurboTheme.bandColor(band).opacity(0.10))

                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 9)

                // Solid stroke — AngularGradient/conic was burning ~25% CPU redrawing offscreen.
                Circle()
                    .trim(from: 0, to: animated ? clamped : 0)
                    .stroke(
                        TurboTheme.bandColor(band),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TurboTheme.bandColor(band))

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
