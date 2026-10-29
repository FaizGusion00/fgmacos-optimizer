import SwiftUI

struct FocusProfileView: View {
    @EnvironmentObject private var appState: AppState

    private let profiles: [FocusProfile] = [.meeting, .coding, .gaming]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    let active = appState.focus.active == profile
                    Button {
                        appState.applyFocus(profile)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: profile.symbol)
                                .font(.system(size: 12, weight: .bold))
                            Text(profile.title)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(active ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(active ? TurboTheme.bandColor(.warn) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isOptimizing)
                }
            }

            HStack {
                if appState.focus.active != .off {
                    Text("\(appState.focus.active.title) active")
                        .font(Design.Text.micro)
                        .foregroundStyle(TurboTheme.bandColor(.warn))
                    Spacer()
                    Button("Off") { appState.applyFocus(.off) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                } else {
                    Text("Meeting · Coding · Gaming — one tap")
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.72))
                }
            }
        }
    }
}
