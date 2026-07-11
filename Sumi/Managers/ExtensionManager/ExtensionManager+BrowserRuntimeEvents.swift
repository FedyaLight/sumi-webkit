import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func notifyWindowOpened(_ windowState: BrowserWindowState) -> Bool {
        browserRuntimeBridgeOwner.notifyWindowOpened(windowState)
    }

    func notifyWindowClosed(_ windowState: BrowserWindowState) {
        browserRuntimeBridgeOwner.notifyWindowClosed(windowState)
    }

    @discardableResult
    func notifyAuxiliaryWindowOpened(
        _ session: AuxiliaryWindowSession
    ) -> Bool {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowOpened(session)
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowFocused(session)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowClosed(session)
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        browserRuntimeBridgeOwner.notifyWindowFocused(windowState)
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        browserRuntimeBridgeOwner.notifyTabActivated(
            newTab: newTab,
            previous: previous
        )
    }

    func notifyTabClosed(_ tab: Tab) {
        browserRuntimeBridgeOwner.notifyTabClosed(tab)
    }

    func reconcileOpenTabsAfterExtensionContextLoad(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileId: UUID? = nil
    ) {
        browserRuntimeBridgeOwner.reconcileOpenTabsAfterExtensionContextLoad(
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded,
            profileId: profileId
        )
    }

    func registerExistingWindowStateIfAttached() {
        browserRuntimeBridgeOwner.registerExistingWindowStateIfAttached()
    }

    func allKnownTabs() -> [Tab] {
        browserRuntimeBridgeOwner.allKnownTabs()
    }

    func liveWebViews(for tab: Tab) -> [WKWebView] {
        browserRuntimeBridgeOwner.liveWebViews(for: tab)
    }

    func pruneRuntimeAdapters() {
        browserRuntimeBridgeOwner.pruneRuntimeAdapters()
    }
}
