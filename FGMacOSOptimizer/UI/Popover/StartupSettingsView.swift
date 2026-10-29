import SwiftUI

struct StartupSettingsView: View {
    @ObservedObject private var launch = LaunchAtLoginStore.shared
    @ObservedObject private var features = FeatureSettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Startup")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            Toggle(isOn: Binding(
                get: { launch.isEnabled },
                set: { launch.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at Login")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Auto-run FGMacOS Optimizer when you start your Mac")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $launch.optimizeOnLaunch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optimize after startup")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Stop Time Machine backups on launch; keep soft Turbo state")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!launch.isEnabled && !launch.optimizeOnLaunch)

            Toggle(isOn: $features.clearDerivedDataOnTurbo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear Derived Data with Turbo")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Off by default — wiping Derived Data can disrupt Xcode builds")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $features.showMenuBarMeters) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show meters in menu bar")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("CPU% and free RAM next to the icon")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let msg = launch.statusMessage {
                Button {
                    launch.openLoginItemsSettings()
                } label: {
                    Label(msg, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(TurboTheme.bandColor(.warn))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { launch.refresh() }
    }
}
