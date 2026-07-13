import Foundation

/// Installs the four independent browser workflows at the WindowRegistry event
/// boundary. The registry retains only the two small terminal-safe workflows;
/// live runtime services are weakly captured.
@MainActor
enum BrowserWindowRegistryBinding {
    @discardableResult
    static func install(
        registration: BrowserWindowSessionRestorationService,
        closing: BrowserWindowCloseWorkflow,
        activity: BrowserWindowActivationService,
        allWindowsClosed: BrowserAllWindowsClosedWorkflow,
        on registry: WindowRegistry
    ) -> WindowRegistry.EventSinkInstallationReceipt? {
        let receipt = registry.installEventSink(
            WindowRegistry.EventSink(
                prepareWindowRegistration: { [weak registration] windowState in
                    registration?.prepareRegistration(windowState)
                },
                publishWindowRegistration: { [weak registration] windowState in
                    registration?.commitRegistration(windowState)
                },
                closeWindow: { [weak registration, weak activity] windowState in
                    registration?.discardRegistration(windowState)
                    activity?.discardDeferredActivation(windowState)
                    closing.handleWindowClose(windowState)
                },
                activateWindow: { [weak activity] windowState in
                    activity?.activate(windowState)
                },
                changeWindowVisibility: { [weak activity] windowState in
                    activity?.handleVisibilityChanged(windowState)
                },
                closeAllWindows: {
                    allWindowsClosed.handleAllWindowsClosed()
                }
            )
        )
        guard let receipt else { return nil }
        registration.restoreRegisteredWindows(registry.allWindows)
        if let activeWindow = registry.activeWindow {
            activity.activate(activeWindow)
        }
        return receipt
    }
}
