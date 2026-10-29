import AppKit
import SwiftUI
import Combine
import UserNotifications
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastMeterTitle = ""
    private var lastMeterUpdate = Date.distantPast

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        setupStatusItem()
        setupPopover()
        bindStatusIcon()
        bindMeters()
        bindAppearance()
        appState.start()
        AppearanceStore.shared.applyNow()
        AppLog.lifeFile("didFinishLaunching pid=\(ProcessInfo.processInfo.processIdentifier) path=\(Bundle.main.bundlePath)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showPopoverFromStatusItem()
            if !PermissionManager.shared.hasCompletedOnboarding {
                PermissionsWindowController.show()
            } else {
                self?.flashLaunchNotice()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopoverFromStatusItem()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLog.lifeFile("applicationShouldTerminate requested")
        return .terminateNow
    }

    func showPopoverFromStatusItem() {
        guard let button = statusItem?.button, let popover, !popover.isShown else { return }
        appState.popoverDidOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startEventMonitor()
    }

    private func flashLaunchNotice() {
        let key = "fg.launch.notice.\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        Task {
            let granted = await PermissionManager.shared.requestNotificationsIfNeeded()
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "FGMacOS Optimizer is running"
            content.body = "Look at the menu bar (top-right) for the gauge / bolt icon."
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "fg.launch.notice",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(req)
            AppLog.lifeFile("posted launch banner notification")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.lifeFile("willTerminate")
        appState.stop()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = StatusBarSymbol.image(turboActive: false)
            button.imagePosition = .imageLeading
            button.toolTip = "FGMacOS Optimizer"
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        AppLog.metrics.info("Status item created (menu bar)")
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: Design.popoverWidth, height: Design.popoverHeight)
        popover.contentViewController = NSHostingController(
            rootView: OptimizerPopoverView()
                .environmentObject(appState)
                .environmentObject(AppearanceStore.shared)
        )
        self.popover = popover
    }

    private func bindStatusIcon() {
        appState.$isTurboActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] turbo in
                self?.updateStatusIcon(turboActive: turbo)
                self?.setBreathingAnimation(active: turbo)
            }
            .store(in: &cancellables)
    }

    private func bindMeters() {
        appState.$displayMetrics
            .combineLatest(FeatureSettingsStore.shared.$showMenuBarMeters, appState.focus.$active)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics, showMeters, focus in
                self?.updateMeters(metrics: metrics, showMeters: showMeters, focus: focus)
            }
            .store(in: &cancellables)
    }

    private func updateMeters(metrics: SystemMetrics, showMeters: Bool, focus: FocusProfile) {
        guard let button = statusItem?.button else { return }
        let now = Date()
        // Throttle title thrash when popover closed.
        if now.timeIntervalSince(lastMeterUpdate) < 2.5, !appState.isOptimizing {
            // still refresh tooltip lightly
        } else {
            lastMeterUpdate = now
            if showMeters, metrics.timestamp > .distantPast {
                let cpu = Int((metrics.cpuUsageFraction * 100).rounded())
                let ram = SystemMetrics.formatGB(metrics.memoryAvailableBytes)
                    .replacingOccurrences(of: " GB", with: "G")
                let title = "\(cpu)% · \(ram)"
                if title != lastMeterTitle {
                    lastMeterTitle = title
                    button.title = " \(title)"
                    button.imagePosition = .imageLeading
                }
            } else {
                if lastMeterTitle != "" {
                    lastMeterTitle = ""
                    button.title = ""
                    button.imagePosition = .imageOnly
                }
            }
        }

        var tip = "FGMacOS Optimizer"
        if focus != .off { tip += " · \(focus.title)" }
        tip += " · CPU \(Int(metrics.cpuUsageFraction * 100))% · RAM \(SystemMetrics.formatGB(metrics.memoryAvailableBytes)) free"
        tip += " · \(metrics.thermalLevel.title) · Pressure \(metrics.memoryPressure.title)"
        button.toolTip = tip
    }

    private func setBreathingAnimation(active: Bool) {
        guard let button = statusItem?.button else { return }
        button.layer?.removeAnimation(forKey: "fg.breath")
        button.wantsLayer = true
        if active {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.55
            anim.duration = 0.9
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(anim, forKey: "fg.breath")
        } else {
            button.alphaValue = 1.0
            button.layer?.opacity = 1.0
        }
    }

    private func bindAppearance() {
        NotificationCenter.default.publisher(for: .fgAppearanceDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let mode = (note.object as? AppAppearance) ?? AppearanceStore.shared.appearance
                self?.applyAppearance(mode)
            }
            .store(in: &cancellables)
    }

    private func applyAppearance(_ mode: AppAppearance) {
        let ns = mode.nsAppearance
        popover?.appearance = ns
        popover?.contentViewController?.view.appearance = ns
        popover?.contentViewController?.view.window?.appearance = ns
        popover?.contentViewController?.view.needsDisplay = true
        popover?.contentViewController?.view.subviews.forEach { $0.needsDisplay = true }
    }

    private func updateStatusIcon(turboActive: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = StatusBarSymbol.image(turboActive: turboActive)
        if turboActive {
            button.contentTintColor = NSColor.systemRed
        } else {
            button.contentTintColor = nil
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            appState.popoverDidOpen()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
        appState.popoverDidClose()
        stopEventMonitor()
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Notifications

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let pid = userInfo["pid"] as? Int32 ?? Int32(userInfo["pid"] as? Int ?? 0)
        Task { @MainActor in
            if response.actionIdentifier == WatchdogEngine.killActionID, pid > 1 {
                await appState.watchdog.forceKillPID(pid)
            } else if response.notification.request.identifier == "fg.smart.ram" {
                appState.freeRAM(skipConfirm: true, fromSmartSuggest: true)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                showPopoverFromStatusItem()
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
