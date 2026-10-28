import SwiftUI
import AppKit
import UserNotifications

struct PermissionsGuideView: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                permissionCard(
                    title: "Notifications",
                    detail: "We’ll alert you when a process sustains very high CPU. Requested only when you tap below — never spammed at launch.",
                    status: notificationLabel,
                    symbol: "bell.badge",
                    actionTitle: permissions.notificationStatus == .denied ? "Open Settings" : "Request Access"
                ) {
                    Task {
                        if permissions.notificationStatus == .denied {
                            permissions.openNotificationsPane()
                        } else {
                            _ = await permissions.requestNotificationsIfNeeded()
                        }
                    }
                }

                permissionCard(
                    title: "Accessibility",
                    detail: "Needed for reliable hung-app (beach ball) detection in Watchdog. macOS will show a system prompt.",
                    status: permissions.accessibilityTrusted ? "Granted" : "Not granted",
                    symbol: "accessibility",
                    actionTitle: "Enable Accessibility"
                ) {
                    permissions.requestAccessibility()
                }

                permissionCard(
                    title: "Full Disk Access",
                    detail: "Required to clear user caches and Xcode Derived Data thoroughly. Add FGMacOS Optimizer in System Settings, then relaunch.",
                    status: permissions.hasCacheAccess() ? "Looks OK" : "Needs grant",
                    symbol: "internaldrive",
                    actionTitle: "Open Full Disk Access"
                ) {
                    permissions.openFullDiskAccess()
                }

                permissionCard(
                    title: "Admin / Automation",
                    detail: "Turbo Mode (Spotlight) and DNS flush ask for your Mac password via a standard admin prompt when you use those features — not before.",
                    status: "On demand",
                    symbol: "lock.shield",
                    actionTitle: "Open Automation Settings"
                ) {
                    permissions.openAutomationPane()
                }

                memoryBudgetNote

                Button("Done") {
                    permissions.hasCompletedOnboarding = true
                    permissions.refresh()
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var notificationLabel: String {
        switch permissions.notificationStatus {
        case .authorized, .provisional: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Grant only what you need. Destructive actions always ask first. Elevated rights only appear when you trigger Turbo or DNS flush.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionCard(
        title: String,
        detail: String,
        status: String,
        symbol: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.system(size: 12))
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

    private var memoryBudgetNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Safety", systemImage: "checkmark.shield")
                .font(.system(size: 13, weight: .semibold))
            Text("Cursor, Terminal, Docker, Xcode and system apps are whitelisted from auto-kill. Cache cleaning only touches an allow-listed set of folders.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}
