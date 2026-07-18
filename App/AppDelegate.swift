//
//  AppDelegate.swift
//  Sumi
//
//  Application lifecycle delegate handling app termination, URL events, and menu routing
//

import AppKit
import OSLog
import UserNotifications
import SumiDomain

/// Handles application-level lifecycle events and coordinates app termination
///
/// Key responsibilities:
/// - **URL Handling**: Opens external URLs (e.g., from other apps, custom URL schemes)
/// - **Mouse Button Events**: Maps mouse buttons 2/3/4 to floating bar, back, and forward
/// - **App Termination**: Coordinates graceful shutdown with data persistence
///
/// Quit path: `applicationShouldTerminate` confirms with AppKit when needed,
/// then keeps termination pending until persistence + WKWebView cleanup finish
/// or the bounded shutdown timeout expires.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let log = Logger.sumi(category: "AppTermination")

    weak var mouseButtonRouter: (any BrowserMouseButtonCommandRouting)?
    weak var externalURLHandler: (any ExternalURLHandling)?
    /// Process-lifetime adapter with only a weak browser-root reference. A
    /// strong runtime lease is acquired synchronously after Quit is confirmed.
    var terminationCoordinator: (any BrowserTerminationCoordinating)?
    weak var appLifecycleHandler: (any BrowserAppLifecycleHandling)?
    weak var settingsHandler: SumiSettingsService?
    var shortcutManager: KeyboardShortcutManager?
    var fallbackPersistenceSave: (@MainActor () throws -> Void)?
    var terminationReply: @MainActor (NSApplication, Bool) -> Void = {
        application,
        shouldTerminate in
        application.reply(toApplicationShouldTerminate: shouldTerminate)
    }

    // Window registry for accessing active window state
    weak var windowRegistry: WindowRegistry?
    private var quitConfirmationInProgress = false
    private let terminationFinalizer: AppTerminationFinalizer
    let sidebarMouseButtonCaptureRegistry = SidebarMouseButtonCaptureRegistry()
    private lazy var mouseButtonRoutingOwner = BrowserMouseButtonRoutingOwner(
        sidebarMouseButtonCaptureRegistry: sidebarMouseButtonCaptureRegistry
    )
    private let urlEventClass = AEEventClass(kInternetEventClass)
    private let urlEventID = AEEventID(kAEGetURL)

    override convenience init() {
        self.init(terminationFinalizer: AppTerminationFinalizer(
            observeReply: { reason in
                switch reason {
                case .completed:
                    AppDelegate.log.info("Termination: durable finalization completed")
                case .timedOut:
                    AppDelegate.log.error(
                        "Termination: durable finalization exceeded bounded timeout"
                    )
                }
            }
        ))
    }

    init(terminationFinalizer: AppTerminationFinalizer) {
        self.terminationFinalizer = terminationFinalizer
        super.init()
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ _: Notification) {
        UNUserNotificationCenter.current().delegate = self
        setupURLEventHandling()
        setupMouseButtonHandling()
        warmUpPublicSuffixList()
        if NSApplication.shared.windows.isEmpty == false {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Parsing the bundled Public Suffix List is a one-time cost; do it off
    /// the main thread at launch so the first omnibar input or permission
    /// lookup does not pay for it.
    private func warmUpPublicSuffixList() {
        Task.detached(priority: .utility) {
            _ = SumiPublicSuffixList.bundled
        }
    }

    func applicationDidBecomeActive(_ _: Notification) {
        appLifecycleHandler?.handleApplicationDidBecomeActive()
    }

    func applicationWillResignActive(_ _: Notification) {
        appLifecycleHandler?.handleApplicationWillResignActive()
    }

    nonisolated func userNotificationCenter(
        _ _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ _: UNUserNotificationCenter,
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
        _ = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self,
                  let mouseButtonRouter = self.mouseButtonRouter,
                  let registry = self.windowRegistry else { return event }

            // Mouse events are delivered on the main thread, so we can safely assume main actor isolation
            _ = MainActor.assumeIsolated {
                self.mouseButtonRoutingOwner.handleOtherMouseDown(
                    event,
                    mouseButtonRouter: mouseButtonRouter,
                    windowRegistry: registry
                )
            }
            return event
        }
    }

    /// Handles URLs opened from external sources (e.g., Finder, other apps)
    func application(_: NSApplication, open urls: [URL]) {
        urls.forEach { handleIncoming(url: $0) }
    }

    // MARK: - Application Termination

    /// Confirms user-initiated quits when enabled, then holds AppKit's
    /// termination request until durable finalization completes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationFinalizer.isFinalizing {
            AppDelegate.log.info("Termination: duplicate quit joined in-flight finalization")
            return .terminateLater
        }
        if terminationFinalizer.didReply {
            return .terminateNow
        }

        terminationCoordinator?.prepareForTermination()
        NotificationCenter.default.post(
            name: .sumiShouldHideCollapsedSidebarOverlay,
            object: sender
        )

        guard shouldAskBeforeQuit else {
            beginTerminationFinalization(for: sender)
            return .terminateLater
        }

        guard !quitConfirmationInProgress else {
            AppDelegate.log.info("Termination: duplicate quit joined pending confirmation")
            return .terminateLater
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
            beginTerminationFinalization(for: sender)
            return .terminateLater
        }
        return .terminateCancel
    }

    private var shouldAskBeforeQuit: Bool {
        settingsHandler?.askBeforeQuit ?? false
    }

    private func setAskBeforeQuit(_ value: Bool) {
        settingsHandler?.askBeforeQuit = value
    }

    private func quitConfirmationWindow() -> NSWindow? {
        windowRegistry?.activeWindow.flatMap { windowRegistry?.appKitWindow(for: $0) } ?? NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func makeQuitConfirmationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to quit Sumi?"
        alert.informativeText = "You may lose unsaved work in your tabs."
        alert.alertStyle = .informational
        alert.icon = quitConfirmationIcon()
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[safe: 1]?.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show it again"
        return alert
    }

    private func quitConfirmationIcon() -> NSImage {
        NSApp.applicationIconImage ?? NSImage()
    }

    private func presentQuitConfirmationSheet(for application: NSApplication, window: NSWindow) {
        let alert = makeQuitConfirmationAlert()
        let terminationReply = self.terminationReply
        alert.beginSheetModal(
            for: window
        ) { [weak self, alert, application, terminationReply] response in
            MainActor.assumeIsolated {
                guard let self else {
                    terminationReply(application, false)
                    return
                }

                self.quitConfirmationInProgress = false
                let shouldTerminate = self.handleQuitConfirmationResponse(response, alert: alert)
                if shouldTerminate {
                    self.beginTerminationFinalization(for: application)
                } else {
                    self.terminationReply(application, false)
                }
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

    func beginTerminationFinalization(for application: NSApplication) {
        guard terminationFinalizer.isFinalizing == false,
              terminationFinalizer.didReply == false
        else { return }

        let finalizationLease = terminationCoordinator?.acquireFinalizationLease()
        let fallbackPersistenceSaveSnapshot = self.fallbackPersistenceSave
        let reply = terminationReply

        _ = terminationFinalizer.begin(
            finalize: {
                await Self.performTerminationFinalization(
                    lease: finalizationLease,
                    fallbackPersistenceSave: fallbackPersistenceSaveSnapshot
                )
            },
            reply: { shouldTerminate in
                reply(application, shouldTerminate)
            }
        )
    }

    private static func performTerminationFinalization(
        lease: (any BrowserTerminationFinalizing)?,
        fallbackPersistenceSave: (@MainActor () throws -> Void)?
    ) async {
        guard let lease else {
            if let fallbackPersistenceSave {
                do {
                    try fallbackPersistenceSave()
                    AppDelegate.log.info("Fallback save without BrowserManager succeeded")
                } catch {
                    AppDelegate.log.error(
                        "Fallback save without BrowserManager failed: \(String(describing: error))"
                    )
                }
            } else {
                AppDelegate.log.info(
                    "Termination: fallback skipped (no runtime lease or fallback save)"
                )
            }
            AppDelegate.log.info("Termination: fallback path complete (no runtime lease)")
            return
        }
        await lease.finalizeTermination()
    }

    func applicationWillTerminate(_: Notification) {
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
