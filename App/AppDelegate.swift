//
//  AppDelegate.swift
//  Sumi
//
//  Application lifecycle delegate handling app termination, URL events, and menu routing
//

import AppKit
import OSLog
import UserNotifications

/// Handles application-level lifecycle events and coordinates app termination
///
/// Key responsibilities:
/// - **URL Handling**: Opens external URLs (e.g., from other apps, custom URL schemes)
/// - **Mouse Button Events**: Maps mouse buttons 2/3/4 to floating bar, back, and forward
/// - **App Termination**: Coordinates graceful shutdown with data persistence
///
/// Quit path: `applicationShouldTerminate` confirms with AppKit when needed, then schedules persistence +
/// WKWebView cleanup on the next main turn.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let log = Logger.sumi(category: "AppTermination")

    weak var commandRouter: (any BrowserCommandRouting)?
    weak var windowRouter: (any WindowCommandRouting)?
    weak var webViewLookup: (any WebViewLookup)?
    weak var externalURLHandler: (any ExternalURLHandling)?
    weak var persistenceHandler: (any BrowserPersistenceHandling)?
    weak var updateHandler: BrowserManager?
    weak var settingsHandler: SumiSettingsService?
    var shortcutManager: KeyboardShortcutManager?

    // Window registry for accessing active window state
    weak var windowRegistry: WindowRegistry?
    private var quitConfirmationInProgress = false

    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setupURLEventHandling()
        setupMouseButtonHandling()
        scheduleCloseMenuConfiguration()
        if NSApplication.shared.windows.isEmpty == false {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleCloseMenuConfiguration()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        RuntimeDiagnostics.debug(
            "Notification response received: \(response.notification.request.identifier)",
            category: "Notifications"
        )
    }

    func applicationDidUpdate(_ notification: Notification) {
        _ = notification
    }

    /// Registers handler for external URL events (e.g., clicking links from other apps)
    private func setupURLEventHandling() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: urlEventClass,
            andEventID: urlEventID
        )
    }

    /// Sets up global mouse button event monitoring for extra physical mouse buttons
    ///
    /// Many mice have extra buttons beyond left/right click. This maps them to browser actions:
    /// - **Button 2** (middle click/scroll wheel button): Open floating bar
    /// - **Button 3** (typically a side button labeled "Back"): Navigate back in history
    /// - **Button 4** (typically a side button labeled "Forward"): Navigate forward in history
    ///
    /// This is common in browsers - side buttons on gaming/office mice are often used for navigation.
    private func setupMouseButtonHandling() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) {
            [weak self] event in
            guard let self = self,
                  let commandRouter = self.commandRouter,
                  let webViewLookup = self.webViewLookup,
                  let registry = self.windowRegistry else { return event }

            // Mouse events are delivered on the main thread, so we can safely assume main actor isolation
            MainActor.assumeIsolated {
                switch event.buttonNumber {
                case 2:  // Middle mouse button
                    if let activeWindow = registry.activeWindow {
                        commandRouter.focusFloatingBar(
                            in: activeWindow,
                            prefill: "",
                            navigateCurrentTab: false
                        )
                    }
                case 3:  // Back button
                    guard
                        let windowState = registry.activeWindow,
                        let currentTab = commandRouter.currentTab(for: windowState),
                        let webView = webViewLookup.webView(for: currentTab.id, in: windowState.id)
                    else {
                        return
                    }
                    webView.goBack()
                case 4:  // Forward button
                    guard
                        let windowState = registry.activeWindow,
                        let currentTab = commandRouter.currentTab(for: windowState),
                        let webView = webViewLookup.webView(for: currentTab.id, in: windowState.id)
                    else {
                        return
                    }
                    webView.goForward()
                default:
                    break
                }
            }
            return event
        }
    }

    private func configureCloseMenuItems() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu else {
            return
        }

        if let closeItem = fileMenu.items.first(where: { $0.title == "Close" }) {
            closeItem.title = "Close Tab"
            closeItem.keyEquivalent = "w"
            closeItem.keyEquivalentModifierMask = [.command]
            closeItem.target = self
            closeItem.action = #selector(handleCloseTabMenuItem(_:))
        }

        if let closeAllItem = fileMenu.items.first(where: { $0.title == "Close All" }) {
            closeAllItem.title = "Close Window"
            closeAllItem.keyEquivalent = "w"
            closeAllItem.keyEquivalentModifierMask = [.command, .shift]
            closeAllItem.target = self
            closeAllItem.action = #selector(handleCloseWindowMenuItem(_:))
        }
    }

    private func scheduleCloseMenuConfiguration() {
        DispatchQueue.main.async { [weak self] in
            self?.configureCloseMenuItems()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.configureCloseMenuItems()
        }
    }

    @MainActor @objc private func handleCloseTabMenuItem(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow,
           windowRegistry?.windows.values.contains(where: { $0.window === keyWindow }) != true
        {
            keyWindow.performClose(sender)
            return
        }
        commandRouter?.closeCurrentTab()
    }

    @MainActor @objc private func handleCloseWindowMenuItem(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow,
           windowRegistry?.windows.values.contains(where: { $0.window === keyWindow }) != true
        {
            keyWindow.performClose(sender)
            return
        }
        windowRouter?.closeActiveWindow()
    }

    /// Handles URLs opened from external sources (e.g., Finder, other apps)
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }

    // MARK: - Application Termination

    /// Confirms user-initiated quits when enabled, then schedules best-effort persistence.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updateHandler?.dismissFloatingBarForActiveWindow(preserveDraft: true)
        NotificationCenter.default.post(
            name: .sumiShouldHideCollapsedSidebarOverlay,
            object: sender
        )

        guard shouldAskBeforeQuit else {
            scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
                shouldTerminate: true
            )
            return .terminateNow
        }

        guard !quitConfirmationInProgress else {
            AppDelegate.log.info("Termination: cancel duplicate quit confirmation request")
            return .terminateCancel
        }

        if let window = quitConfirmationWindow() {
            quitConfirmationInProgress = true
            sender.activate(ignoringOtherApps: true)
            presentQuitConfirmationSheet(for: sender, window: window)
            return .terminateLater
        }

        let alert = makeQuitConfirmationAlert()
        let shouldTerminate = handleQuitConfirmationResponse(alert.runModal(), alert: alert)
        if shouldTerminate {
            scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
                shouldTerminate: true
            )
            return .terminateNow
        }
        return .terminateCancel
    }

    private var shouldAskBeforeQuit: Bool {
        settingsHandler?.askBeforeQuit ?? updateHandler?.sumiSettings?.askBeforeQuit ?? false
    }

    private func setAskBeforeQuit(_ value: Bool) {
        if let settingsHandler {
            settingsHandler.askBeforeQuit = value
        } else {
            updateHandler?.sumiSettings?.askBeforeQuit = value
        }
    }

    private func quitConfirmationWindow() -> NSWindow? {
        windowRegistry?.activeWindow?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func makeQuitConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to quit Sumi?"
        alert.informativeText = "You may lose unsaved work in your tabs."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[safe: 1]?.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show it again"
        return alert
    }

    private func presentQuitConfirmationSheet(for application: NSApplication, window: NSWindow) {
        let alert = makeQuitConfirmationAlert()
        alert.beginSheetModal(for: window) { [weak self, alert, application] response in
            MainActor.assumeIsolated {
                guard let self else {
                    application.reply(toApplicationShouldTerminate: false)
                    return
                }

                self.quitConfirmationInProgress = false
                let shouldTerminate = self.handleQuitConfirmationResponse(response, alert: alert)
                if shouldTerminate {
                    self.scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
                        shouldTerminate: true
                    )
                }

                application.reply(toApplicationShouldTerminate: shouldTerminate)
            }
        }
    }

    private func handleQuitConfirmationResponse(
        _ response: NSApplication.ModalResponse,
        alert: NSAlert
    ) -> Bool {
        if alert.suppressionButton?.state == .on {
            setAskBeforeQuit(false)
        }

        let shouldTerminate = response == .alertFirstButtonReturn
        guard shouldTerminate else {
            AppDelegate.log.info("Termination: cancelled by quit confirmation")
            return false
        }
        return true
    }

    /// Best-effort persistence and WK teardown after `applicationShouldTerminate` returns (next main turn).
    private func scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
        shouldTerminate: Bool
    ) {
        let persistenceHandlerSnapshot = self.persistenceHandler
        let updateHandlerSnapshot = self.updateHandler

        DispatchQueue.main.async {
            Task { @MainActor in
                guard shouldTerminate else {
                    AppDelegate.log.info("Termination: cancel (shouldTerminate false)")
                    return
                }

                guard let persistenceHandler = persistenceHandlerSnapshot else {
                    do {
                        let ctx = SumiStartupPersistence.shared.container.mainContext
                        try ctx.save()
                        AppDelegate.log.info("Fallback save without BrowserManager succeeded")
                    } catch {
                        AppDelegate.log.error(
                            "Fallback save without BrowserManager failed: \(String(describing: error))"
                        )
                    }
                    AppDelegate.log.info("Termination: fallback path complete (no persistenceHandler)")
                    return
                }

                AppDelegate.log.info("Termination: MainActor task began")

                persistenceHandler.flushPendingWindowSessionPersistence()

                let runtimePersistStart = CFAbsoluteTimeGetCurrent()
                let flushedRuntimeStates = await persistenceHandler
                    .flushRuntimeStatePersistenceAwaitingResult()
                let rdt = CFAbsoluteTimeGetCurrent() - runtimePersistStart
                AppDelegate.log.info(
                    "Runtime-state persistence flushed \(flushedRuntimeStates) tab(s) in \(String(format: "%.3f", rdt))s"
                )

                let persistStart = CFAbsoluteTimeGetCurrent()
                let didDirectFullReconcile: Bool = await persistenceHandler.persistFullReconcileAwaitingResult(
                    reason: "app termination"
                )
                let pdt = CFAbsoluteTimeGetCurrent() - persistStart
                AppDelegate.log.info(
                    "Full reconcile persistence \(didDirectFullReconcile ? "succeeded" : "used recovery fallback") in \(String(format: "%.3f", pdt))s"
                )

                AppDelegate.log.info("Termination: MainActor finalize (context save + cleanup)")

                let contextSaveStart = CFAbsoluteTimeGetCurrent()
                do {
                    try persistenceHandler.modelContext.save()
                    let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                    AppDelegate.log.info("Context save completed in \(String(format: "%.3f", sdt))s")
                } catch {
                    let sdt = CFAbsoluteTimeGetCurrent() - contextSaveStart
                    AppDelegate.log.error(
                        "Context save failed in \(String(format: "%.3f", sdt))s: \(String(describing: error))"
                    )
                }

                await updateHandlerSnapshot?.performSiteDataPolicyAllWindowsClosedCleanup()
                persistenceHandler.cleanupAllTabs()
                AppDelegate.log.info("Cleanup completed; WKWebView processes terminated")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.log.info("applicationWillTerminate called")
    }

    // MARK: - External URL Handling

    /// Handles URL events from AppleScript/AppleEvents
    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard let stringValue = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: stringValue)
        else {
            return
        }
        handleIncoming(url: url)
    }

    /// Routes incoming external URLs to the browser manager
    private func handleIncoming(url: URL) {
        guard let externalURLHandler else {
            return
        }
        Task { @MainActor in
            externalURLHandler.presentExternalURL(url)
        }
    }
}
