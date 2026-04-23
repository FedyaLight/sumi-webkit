//
//  AppDelegate.swift
//  Sumi
//
//  Application lifecycle delegate handling app termination, URL events, and menu routing
//

import AppKit
import OSLog

/// Handles application-level lifecycle events and coordinates app termination
///
/// Key responsibilities:
/// - **URL Handling**: Opens external URLs (e.g., from other apps, custom URL schemes)
/// - **Mouse Button Events**: Maps mouse buttons 2/3/4 to command palette, back, and forward
/// - **App Termination**: Coordinates graceful shutdown with data persistence
///
/// Quit path: `applicationShouldTerminate` returns `.terminateNow` immediately; persistence + WKWebView
/// cleanup run from `DispatchQueue.main.async` + `Task { @MainActor }` on the next main turn.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger.sumi(category: "AppTermination")

    weak var commandRouter: (any BrowserCommandRouting)?
    weak var windowRouter: (any WindowCommandRouting)?
    weak var webViewLookup: (any WebViewLookup)?
    weak var externalURLHandler: (any ExternalURLHandling)?
    weak var persistenceHandler: (any BrowserPersistenceHandling)?
    weak var updateHandler: BrowserManager?
    var shortcutManager: KeyboardShortcutManager?

    // Window registry for accessing active window state
    weak var windowRegistry: WindowRegistry?
    private let historyMenuInstaller = SumiHistoryMenuInstaller()
    private var didSetupHistoryMenuMonitoring = false
    private var historyMenuRestoreScheduled = false
    private var historyMenuRestoreNeedsForce = false
    private var historyMenuObservers: [NSObjectProtocol] = []

    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)

    deinit {
        for observer in historyMenuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupURLEventHandling()
        setupMouseButtonHandling()
        setupHistoryMenuMonitoring()
        scheduleCloseMenuConfiguration()
        scheduleHistoryMenuConfiguration()
        if NSApplication.shared.windows.isEmpty == false {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleCloseMenuConfiguration()
        scheduleHistoryMenuConfiguration()
    }

    func applicationDidUpdate(_ notification: Notification) {
        configureHistoryMenuIfNeeded()
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
    /// - **Button 2** (middle click/scroll wheel button): Open command palette
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
                        commandRouter.openCommandPalette(
                            in: activeWindow,
                            reason: .keyboard,
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

    private func configureHistoryMenu() {
        historyMenuInstaller.browserManager = updateHandler
        historyMenuInstaller.shortcutManager = shortcutManager
        historyMenuInstaller.actionTarget = self
        historyMenuInstaller.installOrUpdateIfNeeded()
    }

    @MainActor
    func refreshHistoryMenu() {
        scheduleHistoryMenuConfiguration()
    }

    private func scheduleHistoryMenuConfiguration(force: Bool = false) {
        historyMenuRestoreNeedsForce = historyMenuRestoreNeedsForce || force
        guard !historyMenuRestoreScheduled else { return }
        historyMenuRestoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let shouldForce = self.historyMenuRestoreNeedsForce
            self.historyMenuRestoreScheduled = false
            self.historyMenuRestoreNeedsForce = false
            self.configureHistoryMenuIfNeeded(force: shouldForce)
        }
    }

    private func configureHistoryMenuIfNeeded(force: Bool = false) {
        guard let mainMenu = NSApp.mainMenu else { return }

        let historyItems = mainMenu.items.filter { $0.title == "History" }
        let currentHistoryMenu = historyItems.first?.submenu as? SumiHistoryMenu
        if let currentHistoryMenu {
            let dependenciesChanged =
                currentHistoryMenu.browserManager !== updateHandler
                || currentHistoryMenu.shortcutManager !== shortcutManager
                || currentHistoryMenu.actionTarget !== self
            guard force || dependenciesChanged || historyItems.count > 1 else { return }
        }

        configureHistoryMenu()
    }

    private func setupHistoryMenuMonitoring() {
        guard !didSetupHistoryMenuMonitoring else { return }
        didSetupHistoryMenuMonitoring = true

        let notificationCenter = NotificationCenter.default
        let mutationHandler: @Sendable (Notification) -> Void = { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleMenuMutation(notification)
            }
        }

        historyMenuObservers = [
            notificationCenter.addObserver(
                forName: NSMenu.didAddItemNotification,
                object: nil,
                queue: .main,
                using: mutationHandler
            ),
            notificationCenter.addObserver(
                forName: NSMenu.didRemoveItemNotification,
                object: nil,
                queue: .main,
                using: mutationHandler
            ),
            notificationCenter.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleMenuDidBeginTracking(notification)
                }
            },
        ]
    }

    private func handleMenuMutation(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        guard shouldRestoreHistoryMenu(afterMutationIn: menu) else { return }
        scheduleHistoryMenuConfiguration()
    }

    private func shouldRestoreHistoryMenu(afterMutationIn menu: NSMenu) -> Bool {
        if menu is SumiHistoryMenu {
            return false
        }

        if menu === NSApp.mainMenu {
            return true
        }

        guard menu.title == "History" else { return false }
        return NSApp.mainMenu?.items.first(where: { $0.title == "History" })?.submenu === menu
    }

    private func handleMenuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        guard isPlaceholderHistoryMenu(menu) else { return }
        configureHistoryMenuIfNeeded(force: true)
    }

    private func isPlaceholderHistoryMenu(_ menu: NSMenu) -> Bool {
        guard !(menu is SumiHistoryMenu) else { return false }
        guard let historyMenuItem = NSApp.mainMenu?.items.first(where: { $0.title == "History" }) else {
            return menu.title == "History"
        }
        return historyMenuItem.submenu === menu
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

    @MainActor @objc func historyGoBack(_ sender: Any?) {
        _ = sender
        updateHandler?.goBackInActiveWindow()
    }

    @MainActor @objc func historyGoForward(_ sender: Any?) {
        _ = sender
        updateHandler?.goForwardInActiveWindow()
    }

    @MainActor @objc func showHistory(_ sender: Any?) {
        _ = sender
        updateHandler?.showHistory()
    }

    @MainActor @objc func openHistoryEntryVisit(_ sender: NSMenuItem) {
        if let visit = sender.representedObject as? HistoryListItem {
            updateHandler?.openHistoryURLFromMenuItem(visit.url)
        } else if let url = sender.representedObject as? URL {
            updateHandler?.openHistoryURLFromMenuItem(url)
        }
    }

    @MainActor @objc func recentlyClosedAction(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? RecentlyClosedItem else {
            return
        }
        updateHandler?.reopenRecentlyClosedItem(item)
    }

    @MainActor @objc func reopenLastClosedTab(_ sender: Any?) {
        _ = sender
        updateHandler?.reopenLastClosedItem()
    }

    @MainActor @objc func reopenAllWindowsFromLastSession(_ sender: Any?) {
        _ = sender
        updateHandler?.reopenAllWindowsFromLastSession()
    }

    @MainActor @objc func clearAllHistory(_ sender: Any?) {
        _ = sender
        updateHandler?.clearAllHistoryFromMenu()
    }

    /// Handles URLs opened from external sources (e.g., Finder, other apps)
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }

    // MARK: - Application Termination

    /// Returns **terminateNow** immediately and schedules persistence on the next main-queue turn.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let reason = NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: kAEQuitReason)

        switch reason?.enumCodeValue {
        case nil:
            scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
                shouldTerminate: true
            )
        default:
            scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
                shouldTerminate: true
            )
        }

        return .terminateNow
    }

    /// Best-effort persistence and WK teardown after `applicationShouldTerminate` returns (next main turn).
    private func scheduleTerminationPersistenceBestEffortAfterReturningFromDelegate(
        shouldTerminate: Bool
    ) {
        let persistenceHandlerSnapshot = self.persistenceHandler

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
