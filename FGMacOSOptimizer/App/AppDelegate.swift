import AppKit
import SwiftUI
import Combine
import UserNotifications
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate, PopoverHost {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastMeterTitle = ""
    private var lastMeterUpdate = Date.distantPast

    // Popover pinning: while an alert / operation / admin sheet is up the popover must not
    // auto-close (transient popovers collapse when the app deactivates — e.g. SecurityAgent).
    private var modalDepth = 0
    private var explicitCloseRequested = false
    private var popoverClosedDuringOperation = false
    private var quitGeneration = 0
    /// The popover auto-opens ~0.6 s after launch; never quit before the user had UI.
    private let launchedAt = Date()
    private let startupGrace: TimeInterval = 6.0

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.registerAll()
        appState.uiHost = self
        appState.launchedAsLoginItem = Self.detectLoginLaunch()
        setupStatusItem()
        setupPopover()
        bindStatusIcon()
        bindMeters()
        bindAppearance()
        bindLifecycle()
        appState.start()
        if FeatureSettingsStore.shared.keepInMenuBar {
            SmartCareScheduler.shared.start()
        }
        AppearanceStore.shared.applyNow()
        #if DEBUG
        DebugAutomation.shared.start(delegate: self)
        #endif
        AppLog.lifeFile("didFinishLaunching pid=\(ProcessInfo.processInfo.processIdentifier) loginLaunch=\(appState.launchedAsLoginItem) path=\(Bundle.main.bundlePath)")

        NotificationCenter.default.addObserver(
            forName: .fgRequestOnDemandQuit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleQuitIfOnDemand() }
        }
        NotificationCenter.default.addObserver(
            forName: .fgOperationDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.operationDidEnd() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if ProcessInfo.processInfo.arguments.contains("--open-cleaner") {
                CleanerWindowController.show(showIntroIfNeeded: true)
            } else if PermissionManager.shared.shouldReopenCleanerAfterRelaunch {
                // Accessibility often needs relaunch before AXIsProcessTrusted flips.
                PermissionManager.shared.clearReopenCleanerFlag()
                PermissionManager.shared.refresh()
                AppLog.lifeFile("post-relaunch \(PermissionManager.shared.permissionSnapshot())")
                if !PermissionManager.shared.accessibilityTrusted {
                    // Stale Settings row (common after ad-hoc rebuild) — guide retoggle.
                    PermissionManager.shared.markAccessibilityRelaunchDidNotApply()
                    PermissionsWindowController.show()
                } else {
                    CleanerWindowController.show(showIntroIfNeeded: true)
                }
            } else if !PermissionManager.shared.hasCompletedOnboarding {
                // Ask permissions early — Continue always available (optional).
                PermissionsWindowController.show()
            } else if FeatureSettingsStore.shared.keepInMenuBar {
                // Only auto-open the menu when the user wants a resident agent.
                self?.showPopoverFromStatusItem()
                self?.flashLaunchNotice()
            } else {
                // On-demand: show UI once so Quit-when-done is obvious, then user closes → app exits.
                self?.showPopoverFromStatusItem()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Login-launch detection

    /// True when macOS started us at login (Open at Login). The launch Apple event carries a
    /// flag for legacy login items; SMAppService launches don't always, so also accept
    /// "login item enabled and the console session began < 3 min ago" (utmpx).
    private static func detectLoginLaunch() -> Bool {
        if let ev = NSAppleEventManager.shared().currentAppleEvent,
           ev.eventClass == AEEventClass(kCoreEventClass),
           ev.eventID == AEEventID(kAEOpenApplication),
           let prop = ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)),
           prop.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        guard LaunchAtLoginStore.shared.isEnabled else { return false }
        return secondsSinceConsoleLogin() < 180
    }

    private static func secondsSinceConsoleLogin() -> TimeInterval {
        setutxent()
        defer { endutxent() }
        var best = TimeInterval.greatestFiniteMagnitude
        while let entry = getutxent() {
            let e = entry.pointee
            guard Int32(e.ut_type) == USER_PROCESS else { continue }
            let line = withUnsafePointer(to: e.ut_line) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(_UTX_LINESIZE)) { String(cString: $0) }
            }
            guard line == "console" else { continue }
            let at = Date(timeIntervalSince1970: TimeInterval(e.ut_tv.tv_sec))
            best = min(best, Date().timeIntervalSince(at))
        }
        return best
    }

    var isPopoverShown: Bool { popover?.isShown == true }
    var debugPopoverView: NSView? { popover?.contentViewController?.view }
    var debugPopoverBehavior: String {
        switch popover?.behavior {
        case .transient?: return "transient"
        case .applicationDefined?: return "applicationDefined"
        case .semitransient?: return "semitransient"
        default: return "none"
        }
    }

    // MARK: - Popover pinning (PopoverHost)

    private var shouldPin: Bool {
        modalDepth > 0 || appState.isOptimizing || SessionAuth.shared.isBusy
    }

    func setModalDepth(_ delta: Int) {
        modalDepth = max(0, modalDepth + delta)
        refreshPin()
    }

    func refreshPin() {
        guard let popover else { return }
        let wanted: NSPopover.Behavior = shouldPin ? .applicationDefined : .transient
        if popover.behavior != wanted { popover.behavior = wanted }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        explicitCloseRequested || !shouldPin
    }

    private func bindLifecycle() {
        // Admin sheet (Unlock button) outside any operation: pin while it's up, re-check quit after.
        SessionAuth.shared.$isBusy
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPin()
                self?.scheduleQuitIfOnDemand()
            }
            .store(in: &cancellables)

        // Cleaner scan/clean finishing is a reason to re-check the on-demand quit.
        CleanerStore.shared.$isScanning
            .combineLatest(CleanerStore.shared.$isCleaning)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.scheduleQuitIfOnDemand() }
            .store(in: &cancellables)

        // Keep in menu bar toggled at runtime: resident-only services follow it.
        FeatureSettingsStore.shared.$keepInMenuBar
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { keep in
                if keep {
                    SmartCareScheduler.shared.start()
                } else {
                    SmartCareScheduler.shared.stop()
                }
                AppLog.lifeFile("keepInMenuBar → \(keep)")
            }
            .store(in: &cancellables)
    }

    private func operationDidEnd() {
        // If the admin sheet collapsed the popover mid-operation, bring the result back
        // instead of quitting silently — the user should see what changed.
        if popoverClosedDuringOperation {
            popoverClosedDuringOperation = false
            if popover?.isShown != true, !FeatureSettingsStore.shared.keepInMenuBar {
                showPopoverFromStatusItem()
                return
            }
        }
        scheduleQuitIfOnDemand()
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
        attachPopoverContent()
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
        // Animating the popover keeps CoreAnimation ticking; content detach handles idle CPU.
        popover.animates = false
        popover.contentSize = NSSize(width: Design.popoverWidth, height: Design.popoverHeight)
        // Start empty — attach SwiftUI only while shown. NSPopover keeps the hosting
        // tree alive when closed; forever animations + gauges were burning ~25–30% CPU.
        popover.contentViewController = NSHostingController(rootView: EmptyView())
        popover.delegate = self
        self.popover = popover
    }

    func popoverDidClose(_ notification: Notification) {
        // Covers Escape / outside-click paths that skip togglePopover.
        AppLog.lifeFile("popover closed (optimizing=\(appState.isOptimizing) explicit=\(explicitCloseRequested))")
        if appState.isOptimizing { popoverClosedDuringOperation = true }
        appState.popoverDidClose()
        detachPopoverContent()
        stopEventMonitor()
        scheduleQuitIfOnDemand()
    }

    /// Default mode: no idle menu-bar agent — quit when UI is gone.
    /// Every guard here is a reason the user still has something on screen or in flight.
    private func scheduleQuitIfOnDemand() {
        guard !FeatureSettingsStore.shared.keepInMenuBar else { return }
        quitGeneration &+= 1
        let generation = quitGeneration
        let sinceLaunch = Date().timeIntervalSince(launchedAt)
        let delay = max(0.35, startupGrace - sinceLaunch)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.quitGeneration else { return }
            guard !FeatureSettingsStore.shared.keepInMenuBar else { return }
            guard NSApp.modalWindow == nil else { return }
            guard !self.appState.isOptimizing, !self.appState.storageScanning else { return }
            guard !SessionAuth.shared.isBusy else { return }
            guard !CleanerStore.shared.isCleaning, !CleanerStore.shared.isScanning else { return }
            guard self.popover?.isShown != true else { return }
            if CleanerWindowController.exists { return }
            if PermissionsWindowController.exists { return }
            AppLog.lifeFile("on-demand quit (popover closed, no other windows)")
            NSApp.terminate(nil)
        }
    }

    private func attachPopoverContent() {
        guard let popover else { return }
        popover.contentViewController = NSHostingController(
            rootView: OptimizerPopoverView()
                .environmentObject(appState)
                .environmentObject(AppearanceStore.shared)
        )
        popover.contentSize = NSSize(width: Design.popoverWidth, height: Design.popoverHeight)
    }

    private func detachPopoverContent() {
        guard let popover else { return }
        // Drop the entire SwiftUI graph so timers/animations/layout stop cold.
        popover.contentViewController = NSHostingController(rootView: EmptyView())
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
        // Use sampler raw metrics (not smoothed display) so menu bar updates without driving SwiftUI gauges.
        appState.sampler.$metrics
            .combineLatest(FeatureSettingsStore.shared.$showMenuBarMeters, appState.focus.$active)
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(2.0), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] metrics, showMeters, focus in
                self?.updateMeters(metrics: metrics, showMeters: showMeters, focus: focus)
            }
            .store(in: &cancellables)

        appState.$operationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, let button = self.statusItem?.button else { return }
                if let status {
                    let short = status.replacingOccurrences(of: "…", with: "")
                    button.toolTip = "\(short) — FGMacOS Optimizer is working"
                    // Compact live cue in the menu bar while busy.
                    if button.title.isEmpty || self.appState.isOptimizing {
                        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
                        button.attributedTitle = NSAttributedString(string: "…", attributes: [
                            .font: font,
                            .foregroundColor: NSColor.systemOrange
                        ])
                    }
                } else {
                    button.toolTip = "FGMacOS Optimizer"
                    // Clear the "…" cue; meters (if on) rewrite their title on the next pass.
                    self.lastMeterTitle = ""
                    button.attributedTitle = NSAttributedString(string: "")
                    button.title = ""
                    button.imagePosition = .imageOnly
                    self.updateMeters(
                        metrics: self.appState.sampler.metrics,
                        showMeters: FeatureSettingsStore.shared.showMenuBarMeters,
                        focus: self.appState.focus.active
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func updateMeters(metrics: SystemMetrics, showMeters: Bool, focus: FocusProfile) {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let force = appState.isOptimizing || lastMeterTitle.isEmpty
        if force || now.timeIntervalSince(lastMeterUpdate) >= 2.5 {
            lastMeterUpdate = now
            if showMeters, metrics.timestamp > .distantPast {
                let cpu = Int((metrics.cpuUsageFraction * 100).rounded())
                let ramGB = Double(metrics.memoryAvailableBytes) / 1_073_741_824.0
                let ram = ramGB >= 10
                    ? String(format: "%.0fG", ramGB)
                    : String(format: "%.1fG", ramGB)
                // Compact: no spaces — `15%·3.5G`
                let title = "\(cpu)%·\(ram)"
                if title != lastMeterTitle {
                    lastMeterTitle = title
                    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                    button.attributedTitle = NSAttributedString(string: title, attributes: [
                        .font: font,
                        .foregroundColor: NSColor.labelColor,
                        .kern: -0.3
                    ])
                    button.imagePosition = .imageLeading
                    button.imageHugsTitle = true
                }
            } else if lastMeterTitle != "" {
                lastMeterTitle = ""
                button.attributedTitle = NSAttributedString(string: "")
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }

        var tip = "FG"
        if focus != .off { tip += " · \(focus.title)" }
        tip += " · CPU \(Int(metrics.cpuUsageFraction * 100))% · \(SystemMetrics.formatGB(metrics.memoryAvailableBytes)) free"
        tip += " · \(metrics.thermalLevel.title)"
        button.toolTip = tip
    }

    private func setBreathingAnimation(active: Bool) {
        // Disabled: infinite CA opacity animation kept the status-item layer dirty and burned CPU.
        guard let button = statusItem?.button else { return }
        button.layer?.removeAnimation(forKey: "fg.breath")
        button.alphaValue = 1.0
        button.layer?.opacity = 1.0
        _ = active
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
            attachPopoverContent()
            appState.popoverDidOpen()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startEventMonitor()
        }
    }

    func closePopover() {
        // Explicit close (status-item click) wins over pinning.
        explicitCloseRequested = true
        defer { explicitCloseRequested = false }
        // Delegate popoverDidClose handles detach + appState.popoverDidClose.
        popover?.performClose(nil)
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                // Keep popover open while an alert / Clean / Turbo / admin sheet is up.
                guard let self, !self.shouldPin else { return }
                self.closePopover()
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
            let id = response.notification.request.identifier
            let action = response.actionIdentifier
            let info = response.notification.request.content.userInfo
            if action == WatchdogEngine.killActionID, pid > 1 {
                await appState.watchdog.forceKillPID(pid)
            } else if id == "fg.smart.ram" {
                appState.freeRAM(skipConfirm: true, fromSmartSuggest: true)
            } else if id == SmartCareScheduler.notificationID
                        || action == SmartCareScheduler.reviewActionID
                        || (info["fg.action"] as? String) == "openSmartCare" {
                SmartCareScheduler.shared.openCleanerForReview()
            } else if action == UNNotificationDefaultActionIdentifier {
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
