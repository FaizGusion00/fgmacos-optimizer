import SwiftUI

struct NetworkPulseView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Network pulse")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 14) {
                Label(NetworkPulseMonitor.formatRate(appState.network.downloadBytesPerSec), systemImage: "arrow.down")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Label(NetworkPulseMonitor.formatRate(appState.network.uploadBytesPerSec), systemImage: "arrow.up")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Button("Flush DNS") {
                    appState.flushDNS()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(appState.isOptimizing)
            }

            if let talker = appState.network.topTalker {
                Text("Top · \(talker.name)")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            } else {
                Text("Top talker · —")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.55))
            }
        }
    }
}
