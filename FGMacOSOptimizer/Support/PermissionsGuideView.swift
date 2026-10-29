import SwiftUI
import AppKit
import UserNotifications

/// First-launch welcome. Permissions optional — Continue always visible and clearly enabled.
struct PermissionsGuideView: View {
    @EnvironmentObject private var permissions: PermissionManager
    @State private var busy = false
    @State private var pollTask: Task<Void, Never>?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    howItWorks
                    optionalNote
                    enableAllButton
                    notificationCard
                    accessibilityCard
                    fdaCard
                    adminCard
                }
                .padding(20)
                .padding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
            }

            stickyFooter
        }
        .frame(minWidth: 480, minHeight: 560)
        .onAppear {
            permissions.refresh()
            startPolling()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                appeared = true
            }
            Task {
                if permissions.notificationStatus == .notDetermined {
                    _ = await permissions.requestNotificationsIfNeeded()
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            AppLog.lifeFile("welcome becameActive \(permissions.permissionSnapshot())")
        }
    }

    private var stickyFooter: some View {
        VStack(spacing: 10) {
            Divider()
            Text("Permissions are optional. Open Cleaner anytime — enable more later from Permissions.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if permissions.accessibilityDisplay == .restartToApply || permissions.accessibilityDisplay == .retoggle {
                let needsRetoggle = permissions.accessibilityDisplay == .retoggle
                Button {
                    if needsRetoggle {
                        permissions.requestAccessibility(openSettings: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            permissions.quitAndRelaunch(openCleaner: true)
                        }
                    } else {
                        permissions.quitAndRelaunch(openCleaner: true)
                    }
                } label: {
                    Label(
                        needsRetoggle
                            ? "Open Settings — then auto Quit & reopen"
                            : "Apply Accessibility — Quit & reopen",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CleanerTheme.heroGradient)
                    )
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
                finishAndOpenCleaner()
            } label: {
                Text("Continue — open Cleaner")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CleanerTheme.heroGradient)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .shadow(color: CleanerTheme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.bar)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: permissions.accessibilityDisplay == .restartToApply)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to FGMacOS Optimizer")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Menu-bar app to free space, speed up your Mac, and clean safely.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to use (30 seconds)", systemImage: "lightbulb.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CleanerTheme.accent)
            bullet("Click the menu-bar icon (gauge / bolt).")
            bullet("Tap Open Cleaner — Smart Care and all tools.")
            bullet("Smart Care: Scan → review checklist → Clean selected.")
            bullet("Left sidebar = more tools (Uninstall, Large files, Dev…).")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CleanerTheme.accent.opacity(0.10))
        )
    }

    private var optionalNote: some View {
        Text("Setup below is recommended, not required. You can Continue with Off / optional.")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.75))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private var notificationCard: some View {
        permissionCard(
            title: "1. Notifications",
            detail: permissions.notificationStatus == .denied
                ? "Optional. Settings → Notifications → FGMacOS Optimizer → Allow — or skip."
                : "Optional alerts for high CPU, memory pressure, and cleanup results.",
            status: permissions.notificationsOK ? "On" : statusText(permissions.notificationStatus),
            symbol: "bell.badge.fill",
            ok: permissions.notificationsOK,
            actionTitle: permissions.notificationStatus == .denied ? "Open Notifications Settings" : "Allow"
        ) {
            Task {
                if permissions.notificationStatus == .denied {
                    permissions.openNotificationsPane()
                } else {
                    _ = await permissions.requestNotificationsIfNeeded()
                }
            }
        }
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionCard(
                title: "2. Accessibility",
                detail: accessibilityDetail,
                status: accessibilityStatusLabel,
                symbol: "accessibility",
                ok: permissions.accessibilityTrusted,
                actionTitle: permissions.accessibilityTrusted
                    ? "Open Settings"
                    : (permissions.accessibilityAwaitingRelaunch ? "Open Settings again" : "Open Accessibility Settings")
            ) {
                permissions.requestAccessibility()
            }

            if !permissions.accessibilityTrusted {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(CleanerTheme.accent)
                    Text(permissions.accessibilityDisplay == .retoggle
                         ? "We already restarted once and Accessibility is still Off for this binary. In Settings: turn FGMacOS Optimizer OFF, then ON again. Then use Retoggle then Quit & reopen. Or Continue — Cleaner works without it."
                         : "System Settings can show ON while this running copy still reads Off. macOS applies Accessibility only after Quit & reopen.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CleanerTheme.accent.opacity(0.08))
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: permissions.accessibilityTrusted)
    }

    private var accessibilityDetail: String {
        switch permissions.accessibilityDisplay {
        case .on:
            return "On — Watchdog can detect hung apps."
        case .restartToApply:
            return "Toggle looks ON in Settings. Press Apply — Quit & reopen so this running copy picks it up."
        case .retoggle:
            return "Settings can show ON for an old install while this build is still Off (updates reset the grant). Toggle FGMacOS Optimizer OFF → ON, then Quit & reopen."
        case .off:
            return "Find FGMacOS Optimizer → toggle ON, then Apply (restart). Optional for Cleaner; needed for hung-app Watchdog."
        }
    }

    private var accessibilityStatusLabel: String {
        switch permissions.accessibilityDisplay {
        case .on: return "On"
        case .restartToApply: return "Restart to apply"
        case .retoggle: return "Retoggle needed"
        case .off: return "Off"
        }
    }

    private var fdaCard: some View {
        permissionCard(
            title: "3. Full Disk Access",
            detail: "Needed for deep clean (Mail/Messages attachments, some leftovers). Add FGMacOS Optimizer, toggle ON.",
            status: permissions.fullDiskLooksOK ? "Looks OK" : "Optional",
            symbol: "internaldrive.fill",
            ok: permissions.fullDiskLooksOK,
            actionTitle: "Open Full Disk Access"
        ) {
            permissions.openFullDiskAccess()
        }
    }

    private var adminCard: some View {
        permissionCard(
            title: "4. Admin password",
            detail: "Asked only when you Free RAM, Turbo, DNS, or thin snapshots — once per unlock session.",
            status: "When needed",
            symbol: "lock.shield.fill",
            ok: true,
            actionTitle: "Automation pane"
        ) {
            permissions.openAutomationPane()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enableAllButton: some View {
        Button {
            busy = true
            Task {
                await permissions.requestAllRecommended()
                busy = false
            }
        } label: {
            HStack {
                if busy { ProgressView().controlSize(.small).tint(.white) }
                Text(busy ? "Opening Settings…" : "Open Settings for recommended permissions")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CleanerTheme.heroGradient)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    private func finishAndOpenCleaner() {
        permissions.hasCompletedOnboarding = true
        permissions.refresh()
        AppLog.lifeFile("continue → cleaner \(permissions.permissionSnapshot())")
        PermissionsWindowController.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            CleanerWindowController.show(showIntroIfNeeded: true)
        }
    }

    private func statusText(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized, .provisional: return "On"
        case .denied: return "Off (optional)"
        case .notDetermined: return "Not yet"
        default: return "—"
        }
    }

    private func permissionCard(
        title: String,
        detail: String,
        status: String,
        symbol: String,
        ok: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ok ? TurboTheme.bandColor(.good) : CleanerTheme.accent)
                    .symbolEffectPulse(ok: ok)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text(status)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ok ? TurboTheme.bandColor(.good) : .secondary)
            }
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private extension View {
    @ViewBuilder
    func symbolEffectPulse(ok: Bool) -> some View {
        if #available(macOS 14.0, *), ok {
            self.symbolEffect(.pulse, options: .repeating.speed(0.4))
        } else {
            self
        }
    }
}
