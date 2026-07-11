import Foundation

/// Installs the four independent browser workflows at the WindowRegistry event
/// boundary. The registry retains only the two small terminal-safe workflows;
/// live runtime services are weakly captured.
@MainActor
enum BrowserWindowRegistryBinding {
    static func install(
        registration: BrowserWindowSessionRestorationService,
        closing: BrowserWindowCloseWorkflow,
        activity: BrowserWindowActivationService,
        allWindowsClosed: BrowserAllWindowsClosedWorkflow,
        on registry: WindowRegistry
    ) {
        precondition(
            registry.prepareWindowRegistration == nil
                && registry.publishWindowRegistration == nil
                && registry.onWindowClose == nil
                && registry.onActiveWindowChange == nil
                && registry.onWindowVisibilityChange == nil
                && registry.onAllWindowsClosed == nil,
            "WindowRegistry browser workflows must be installed exactly once"
        )

        registry.prepareWindowRegistration = { [weak registration] windowState in
            registration?.prepareRegistration(windowState)
        }
        registry.publishWindowRegistration = { [weak registration] windowState in
            registration?.commitRegistration(windowState)
        }
        registry.onWindowClose = { [weak registration, weak activity] windowState in
            registration?.discardRegistration(windowState)
            activity?.discardDeferredActivation(windowState)
            closing.handleWindowClose(windowState)
        }
        registry.onActiveWindowChange = { [weak activity] windowState in
            activity?.activate(windowState)
        }
        registry.onWindowVisibilityChange = { [weak activity] windowState in
            activity?.handleVisibilityChanged(windowState)
        }
        registry.onAllWindowsClosed = {
            allWindowsClosed.handleAllWindowsClosed()
        }
        registration.restoreRegisteredWindows(registry.allWindows)
        if let activeWindow = registry.activeWindow {
            activity.activate(activeWindow)
        }
    }
}
