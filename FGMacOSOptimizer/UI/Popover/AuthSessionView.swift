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
                        Label("Unlock", systemImage: biometrySymbol)
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

            if !auth.touchIDForSudoEnabled, auth.prefersBiometrics {
                Button {
                    Task { _ = await auth.enableTouchIDForSudo() }
                } label: {
                    Label("Enable Touch ID for Terminal sudo", systemImage: "touchid")
                        .font(Design.Text.micro)
                }
                .buttonStyle(.borderless)
                .disabled(auth.isBusy)
            }

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
            return auth.privilegeVerified ? "Admin unlocked · root OK" : "Admin unlocked"
        }
        return "Admin locked"
    }

    private var statusLine: String {
        if auth.isSessionValid {
            let m = auth.remainingSeconds / 60
            let s = auth.remainingSeconds % 60
            let via: String
            switch auth.unlockMethod {
            case .touchID: via = biometryLabelShort
            case .password: via = "password"
            case .unknown: via = "admin"
            }
            return String(format: "Via %@ · %d:%02d left", via, m, s)
        }
        return auth.prefersBiometrics
            ? "Tap Unlock — \(auth.biometryLabel) first, then admin confirm"
            : "Tap Unlock — admin password once"
    }

    private var helpLine: String {
        if auth.isSessionValid, let detail = auth.lastProbeDetail {
            return "Verified \(detail). Free RAM / Turbo reuse this session."
        }
        if auth.prefersBiometrics {
            return "\(auth.biometryLabel) confirms it’s you. macOS may still show an admin password sheet once for root tools (system limit)."
        }
        return "Admin password once unlocks Free RAM / Turbo for the period above."
    }

    private var biometryLabelShort: String {
        switch auth.biometryLabel {
        case "Face ID": return "Face ID"
        case "Optic ID": return "Optic ID"
        case "Touch ID": return "Touch ID"
        default: return "password"
        }
    }

    private var biometrySymbol: String {
        switch auth.biometryLabel {
        case "Face ID": return "faceid"
        case "Optic ID": return "opticid"
        case "Touch ID": return "touchid"
        default: return "key.fill"
        }
    }
}
