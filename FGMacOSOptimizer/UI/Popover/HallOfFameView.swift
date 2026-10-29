import SwiftUI

struct HallOfFameView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = FeatureSettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("24h CPU hall of fame")
                    .font(Design.Text.section)
                    .foregroundStyle(.primary.opacity(0.75))
                Spacer()
                Toggle("Pause", isOn: $settings.historyCollectionPaused)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Pause history collection")
            }

            if appState.history.hallOfFame.isEmpty {
                Text("Collecting samples… use your Mac normally")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
            } else {
                ForEach(appState.history.hallOfFame.prefix(5)) { entry in
                    HStack {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f", entry.score))
                            .font(Design.Text.micro)
                            .monospacedDigit()
                            .foregroundStyle(.primary.opacity(0.65))
                    }
                }
            }

            HStack {
                Button("Quit leftovers") {
                    appState.quitLeftovers()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(appState.isOptimizing)

                Button("Clear") {
                    appState.history.clear()
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }

            Text("Leftovers: Zoom, Slack, Teams, Chrome Helper — never whitelist.")
                .font(Design.Text.micro)
                .foregroundStyle(.primary.opacity(0.6))
        }
    }
}
