import SwiftUI

struct AuthSessionView: View {
    @ObservedObject private var auth = SessionAuth.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Security")
                .font(Design.Text.section)
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 10) {
                Image(systemName: auth.isSessionValid ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(auth.isSessionValid ? TurboTheme.bandColor(.good) : .secondary)
                    .font(.system(size: 16, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleLine)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(statusLine)
                            .font(Design.Text.micro)
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                }

                Spacer()

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

            Picker("Remember for", selection: $auth.sessionMinutes) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Text(helpLine)
                .font(Design.Text.micro)
                .foregroundStyle(.primary.opacity(0.72))
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
        }
    }

    private var titleLine: String {
        if auth.isSessionValid {
            return auth.privilegeVerified ? "Admin unlocked · ready" : "Admin unlocked"
        }
        return "Admin locked"
    }

    private var statusLine: String {
        if auth.isSessionValid {
            let m = auth.remainingSeconds / 60
            let s = auth.remainingSeconds % 60
            return String(format: "No more prompts · %d:%02d left", m, s)
        }
        return "Tap Unlock — one admin prompt only"
    }

    private var helpLine: String {
        if auth.isSessionValid, let detail = auth.lastProbeDetail {
            return "\(detail). Free RAM / Turbo reuse this window."
        }
        // Honest: SecurityAgent log on this Mac says "TouchID is not enabled" for admin elevation.
        return "One admin unlock for the period above. macOS often uses password for root tools (Touch ID is app-login only)."
    }
}
