import SwiftUI

struct SmartRAMView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = FeatureSettingsStore.shared

    private var pressure: MemoryPressureLevel { appState.displayMetrics.memoryPressure }
    private var suggest: Bool { pressure >= .warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smart Free RAM")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            HStack {
                Image(systemName: pressure == .critical ? "exclamationmark.triangle.fill" : "memorychip")
                    .foregroundStyle(TurboTheme.bandColor(pressure.band))
                Text("Pressure · \(pressure.title)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                if suggest {
                    Button("Free RAM now") {
                        appState.freeRAM(skipConfirm: true, fromSmartSuggest: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            Toggle(isOn: $settings.autoFreeRAMWhenCritical) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Free RAM when critical")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Off by default · 30 min cooldown · one purge per trigger")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
