import SwiftUI

struct ThermalStoryView: View {
    @EnvironmentObject private var appState: AppState

    private var topCPU: String {
        appState.topProcesses.first.map { "\($0.name) \(Int($0.cpuPercent))%" } ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thermal")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(TurboTheme.bandColor(appState.displayMetrics.thermalLevel.band))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appState.displayMetrics.thermalLevel.title) · \(PowerModeHelper.powerModeTitle)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Likely heat source · \(topCPU)")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer()
                Button("Cool down") {
                    appState.coolDown()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(appState.isOptimizing)
            }

            Text("Kills elevated hogs (whitelist-safe) and enables Low Power on battery.")
                .font(Design.Text.micro)
                .foregroundStyle(.primary.opacity(0.65))
        }
    }
}
