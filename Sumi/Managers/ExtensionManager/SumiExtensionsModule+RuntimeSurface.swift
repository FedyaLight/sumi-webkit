import AppKit
import Foundation
import WebKit

@MainActor
extension SumiExtensionsModule {
    func normalTabUserScripts() -> [SumiPageScript] {
        runtimeSurface.normalTabUserScripts()
    }

    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID? = nil,
        reason: String
    ) {
        runtimeSurface.prepareWebViewConfiguration(
            configuration,
            profileID: profileId,
            reason: reason
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        runtimeSurface.prepareWebView(webView, currentURL: currentURL, reason: reason)
    }

    func prepareExtensionPageNavigationIfNeeded(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        runtimeSurface.prepareExtensionPageNavigation(
            tab,
            targetURL: targetURL,
            reason: reason
        )
    }

    func registerTabWithExtensionRuntimeIfLoaded(_ tab: Tab, reason: String) {
        runtimeSurface.registerTab(tab, reason: reason)
    }

    func reconcileExtensionRuntimeOnUserGestureIfNeeded(
        _ tab: Tab,
        reason: String
    ) {
        runtimeSurface.reconcileOnUserGesture(tab, reason: reason)
    }

    func publishWindowIfLoaded(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        runtimeSurface.publishWindow(windowState)
    }

    func notifyWindowOpenedIfLoaded(_ windowState: BrowserWindowState) -> Bool {
        runtimeSurface.notifyWindowOpened(windowState)
    }

    func notifyWindowClosedIfLoaded(_ windowState: BrowserWindowState) {
        runtimeSurface.notifyWindowClosed(windowState)
    }

    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState) {
        runtimeSurface.notifyWindowFocused(windowState)
    }

    func switchProfileIfLoaded(_ profile: Profile) {
        runtimeSurface.switchProfile(profile)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        runtimeSurface.notifyTabActivated(newTab: newTab, previous: previous)
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        runtimeSurface.notifyTabClosed(tab)
    }

    func notifyTabPropertiesChangedIfLoaded(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        runtimeSurface.publishTabPropertiesIfResident(tab, properties: properties)
    }

    func performExtensionKeyboardCommandIfLoaded(for event: NSEvent) -> Bool {
        runtimeSurface.performKeyboardCommand(for: event)
    }

    func pageContextMenuItemsIfLoaded(for tab: Tab) -> [NSMenuItem] {
        runtimeSurface.pageContextMenuItems(for: tab)
    }

    func markTabEligibleAfterCommittedNavigationIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        runtimeSurface.admitTabAfterCommittedNavigation(tab, reason: reason)
    }

    func prepareExtensionRuntimeBeforeCommittedMainFrameNavigationIfLoaded(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        runtimeSurface.prepareBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: destinationURL,
            reason: reason
        )
    }

    func ensureInitialExtensionContextsIfNeeded(profileId: UUID) async {
        await runtimeSurface.ensureInitialExtensionContexts(profileID: profileId)
    }

    func needsInitialDocumentExtensionContextLoadIfNeeded(profileId: UUID) -> Bool {
        runtimeSurface.needsInitialDocumentExtensionContextLoad(profileID: profileId)
    }

    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL) -> Bool {
        runtimeSurface.consumeRecentlyOpenedExtensionTabRequest(for: url)
    }

    func registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        runtimeSurface.registerExtensionCreatedTab(tab, reason: reason)
    }

    func prepareInitialTabExtensionPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> InitialTabExtensionPreparation {
        runtimeSurface.prepareInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            reason: reason
        )
    }

    func cancelNativeMessagingSessionsIfLoaded(reason: String) {
        runtimeSurface.cancelNativeMessagingSessions(reason: reason)
    }
}
