import SwiftUI

struct AuthSessionView: View {
    @ObservedObject private var auth = SessionAuth.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Security")
                    .font(Design.Text.section)
                    .foregroundStyle(.primary.opacity(0.75))
                Spacer(minLength: 0)
                if auth.isBusy {
                    ProgressView().controlSize(.mini)
                } else if auth.isSessionValid {
                    Button("Lock") { auth.lock() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                } else {
                    Button {
                        Task {
                            _ = await auth.ensureAuthorized(
                                reason: "Unlock FGMacOS Optimizer for Turbo, Free RAM, and DNS flush."
                            )
                        }
                    } label: {
                        Label("Unlock", systemImage: "key.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: auth.isSessionValid ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(auth.isSessionValid ? TurboTheme.bandColor(.good) : .secondary)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(titleLine)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    // countdownTick forces redraw every second while unlocked.
                    Text(statusLine)
                        .font(Design.Text.micro)
                        .foregroundStyle(.primary.opacity(0.7))
                        .monospacedDigit()
                        .id(auth.countdownTick)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("Remember")
                    .font(Design.Text.micro)
                    .foregroundStyle(.primary.opacity(0.7))
                Picker("", selection: $auth.sessionMinutes) {
                    ForEach(SessionAuth.allowedMinutes, id: \.self) { m in
                        Text("\(m)m").tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .labelsHidden()
            }

            Text(helpLine)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            if let err = auth.lastError, !auth.isSessionValid {
                Text(err)
                    .font(Design.Text.micro)
                    .foregroundStyle(TurboTheme.bandColor(.bad))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            auth.refreshBiometryLabel()
            auth.refreshTouchIDForSudoStatus()
            _ = auth.remainingSeconds
        }
    }

    private var titleLine: String {
        auth.isSessionValid ? "Admin unlocked" : "Admin locked"
    }

    private var statusLine: String {
        if auth.isSessionValid {
            let total = auth.remainingSeconds
            let m = total / 60
            let s = total % 60
            return String(format: "%d:%02d left · no more prompts", m, s)
        }
        return "One admin prompt for \(auth.sessionMinutes) min"
    }

    private var helpLine: String {
        if auth.isSessionValid {
            return "Free RAM / Turbo reuse this window until timer ends."
        }
        return "Password is normal for admin tools. Changing \(auth.sessionMinutes)m resizes an open session from unlock time."
    }
}
