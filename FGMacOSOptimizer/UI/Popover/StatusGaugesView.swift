import SwiftUI

struct StatusGaugesView: View {
    let metrics: SystemMetrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse = false

    private var primary: Color { TurboTheme.primaryLabel(for: colorScheme) }
    private var secondary: Color { TurboTheme.secondaryLabel(for: colorScheme) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(TurboTheme.bandColor(.good))
                        .frame(width: 7, height: 7)
                        .opacity(pulse ? 1 : 0.35)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    Text("LIVE")
                        .font(Design.Text.micro)
                        .foregroundStyle(primary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let age = max(0, Int(context.date.timeIntervalSince(metrics.timestamp)))
                        Text(age < 2 ? "· just now" : "· \(age)s ago")
                            .font(Design.Text.micro)
                            .foregroundStyle(secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                if metrics.batteryHasBattery {
                    Label(
                        "\(Int(metrics.batteryPercent * 100))%",
                        systemImage: metrics.batteryCharging ? "battery.100.bolt" : "battery.100"
                    )
                    .font(Design.Text.micro)
                    .foregroundStyle(primary)
                }
            }
            .onAppear { pulse = true }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                CircularGauge(
                    title: "RAM",
                    value: metrics.memoryUsedFraction,
                    band: metrics.memoryPressureColorBand,
                    centerText: "\(Int((metrics.memoryUsedFraction * 100).rounded()))%",
                    caption: "\(SystemMetrics.formatGB(metrics.memoryAvailableBytes)) free",
                    symbol: "memorychip.fill"
                )
                CircularGauge(
                    title: "CPU",
                    value: metrics.cpuUsageFraction,
                    band: metrics.cpuColorBand,
                    centerText: "\(Int((metrics.cpuUsageFraction * 100).rounded()))%",
                    caption: "live",
                    symbol: "cpu.fill"
                )
                CircularGauge(
                    title: "Disk",
                    value: metrics.diskUsedFraction,
                    band: metrics.diskColorBand,
                    centerText: "\(Int((metrics.diskUsedFraction * 100).rounded()))%",
                    caption: "\(SystemMetrics.formatGB(metrics.diskAvailableBytes)) free",
                    symbol: "internaldrive.fill"
                )
                CircularGauge(
                    title: "Thermal",
                    value: metrics.thermalLevel.fraction,
                    band: metrics.thermalLevel.band,
                    centerText: metrics.thermalLevel.title,
                    caption: "system",
                    symbol: "thermometer.medium"
                )
            }
            .animation(MotionTokens.gauge, value: metrics.cpuUsageFraction)
            .animation(MotionTokens.gauge, value: metrics.memoryUsedFraction)
            .animation(MotionTokens.gauge, value: metrics.diskUsedFraction)

            MemoryBreakdownBar(metrics: metrics)
            DiskBreakdownBar(metrics: metrics)
        }
    }
}

private struct MemoryBreakdownBar: View {
    let metrics: SystemMetrics
    private var total: Double { max(1, Double(metrics.memoryTotalBytes)) }
    private var appPart: Double { min(1, Double(metrics.memoryAppUsedBytes) / total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RAM")
                .font(Design.Text.micro)
                .foregroundStyle(.primary.opacity(0.8))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.50, blue: 1.0), Color(red: 0.40, green: 0.70, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * appPart))
                        .animation(MotionTokens.gauge, value: appPart)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                Text("In use \(SystemMetrics.formatGB(metrics.memoryAppUsedBytes))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(SystemMetrics.formatGB(metrics.memoryAvailableBytes)) / \(SystemMetrics.formatGB(metrics.memoryTotalBytes)) free")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
                    .monospacedDigit()
            }

            if metrics.hasSwapPressure {
                Label("Swap \(SystemMetrics.formatGB(metrics.swapUsedBytes)) — RAM tight", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(TurboTheme.bandColor(.warn))
            }
        }
    }
}

private struct DiskBreakdownBar: View {
    let metrics: SystemMetrics
    private var total: Double { max(1, Double(metrics.diskTotalBytes)) }
    private var usedPart: Double { min(1, Double(metrics.diskTotalBytes &- min(metrics.diskTotalBytes, metrics.diskAvailableBytes)) / total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Disk")
                .font(Design.Text.micro)
                .foregroundStyle(.primary.opacity(0.8))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.orange.opacity(0.85), Color.orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * usedPart))
                        .animation(MotionTokens.gauge, value: usedPart)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                Text("Used \(SystemMetrics.formatGB(metrics.diskTotalBytes > metrics.diskAvailableBytes ? metrics.diskTotalBytes - metrics.diskAvailableBytes : 0))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(SystemMetrics.formatGB(metrics.diskAvailableBytes)) free of \(SystemMetrics.formatGB(metrics.diskTotalBytes))")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
                    .monospacedDigit()
            }
        }
    }
}
