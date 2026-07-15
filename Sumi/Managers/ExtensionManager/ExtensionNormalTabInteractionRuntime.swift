import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabInteractionRuntime {
    private let lifecycle:
        ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    private let requestedTabs:
        ExtensionBrowserAttachmentAuthority.RequestedTabs
    private let keyboard: ExtensionKeyboardCommandDispatchOwner
    private let recentRequests: ExtensionRecentTabRequestHistory

    init(
        lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs,
        keyboard: ExtensionKeyboardCommandDispatchOwner,
        recentRequests: ExtensionRecentTabRequestHistory
    ) {
        self.lifecycle = lifecycle
        self.requestedTabs = requestedTabs
        self.keyboard = keyboard
        self.recentRequests = recentRequests
    }

    func reconcileOnUserGesture(_ tab: Tab, reason: String) {
        lifecycle.reconcileOnUserGestureIfNeeded(tab, reason: reason)
    }

    func publishProperties(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        lifecycle.publishProperties(for: tab, requested: properties)
    }

    func performKeyboardCommand(for event: NSEvent) -> Bool {
        keyboard.performCommand(for: event)
    }

    func pageContextMenuItems(for tab: Tab) -> [NSMenuItem] {
        requestedTabs.pageContextMenuItems(for: tab)
    }

    func admitAfterCommittedNavigation(_ tab: Tab, reason: String) {
        lifecycle.markEligibleAfterCommittedNavigation(tab, reason: reason)
    }

    func prepareBeforeCommittedNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        lifecycle.prepareBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: destinationURL,
            reason: reason
        )
    }

    func consumeRecentRequest(for url: URL) -> Bool {
        recentRequests.consume(url)
    }
}
