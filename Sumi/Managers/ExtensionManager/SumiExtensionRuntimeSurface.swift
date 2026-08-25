import AppKit
import Foundation
import WebKit

/// Browser-runtime integration for the optional extension subsystem.
///
/// Every operation is fail-closed when the module is disabled or its manager
/// is not resident. Normal browser activity never materializes the optional
/// runtime unless persisted extension demand already exists.
@MainActor
final class SumiExtensionRuntimeSurface {
    private let lifetime: SumiExtensionManagerLifetime

    init(lifetime: SumiExtensionManagerLifetime) {
        self.lifetime = lifetime
    }

    func normalTabUserScripts() -> [SumiPageScript] {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation.userScripts
            ?? []
    }

    func prepareWebViewConfiguration(
        _ configuration: WKWebViewConfiguration,
        profileID: UUID?,
        reason: String
    ) {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation
            .prepareConfiguration(
                configuration,
                profileID: profileID,
                reason: reason
            )
    }

    func prepareWebView(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation
            .prepareWebView(
                webView,
                currentURL: currentURL,
                reason: reason
            )
    }

    func prepareExtensionPageNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation
            .preparePageNavigation(
            tab,
            targetURL: targetURL,
            reason: reason
        ) ?? .notNeeded
    }

    func registerTab(_ tab: Tab, reason: String) {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation.register(
            tab,
            reason: reason
        )
    }

    func reconcileOnUserGesture(_ tab: Tab, reason: String) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .reconcileOnUserGesture(tab, reason: reason)
    }

    func publishWindow(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication
            .publishWindow(windowState)
            ?? .notParticipating
    }

    func notifyWindowOpened(_ windowState: BrowserWindowState) -> Bool {
        if case .published = publishWindow(windowState) {
            return true
        }
        return false
    }

    func notifyWindowClosed(_ windowState: BrowserWindowState) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication
            .closeWindow(windowState)
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication
            .focusWindow(windowState)
    }

    func switchProfile(
        _ profile: Profile,
        mutationLease: ProfileReferenceMutationLease? = nil
    ) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication
            .switchProfile(profile, mutationLease: mutationLease)
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication.activateTab(
            newTab,
            previous: previous
        )
    }

    func notifyTabClosed(_ tab: Tab) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.publication.closeTab(tab)
    }

    func publishTabPropertiesIfResident(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .publishProperties(tab, properties: properties)
    }

    func performKeyboardCommand(for event: NSEvent) -> Bool {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .performKeyboardCommand(for: event) ?? false
    }

    func admitTabAfterCommittedNavigation(_ tab: Tab, reason: String) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .admitAfterCommittedNavigation(tab, reason: reason)
    }

    func prepareBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .prepareBeforeCommittedNavigation(
                tab,
                destinationURL: destinationURL,
                reason: reason
            )
    }

    func ensureInitialExtensionContexts(profileID: UUID) async
        -> PageNavigationPrerequisiteResult {
        guard lifetime.isEnabled else { return .ready }
        return await lifetime.browserRuntimeIfNeededForNormalTab()?
            .initialDocument.ensureInitialContexts(profileID: profileID)
            ?? .ready
    }

    func ensureInitialTabPublication(
        _ tab: Tab,
        reason: String
    ) async -> PageNavigationPrerequisiteResult {
        guard lifetime.isEnabled else { return .ready }
        return await lifetime.browserRuntimeIfNeededForNormalTab()?
            .initialDocument.ensureInitialTabPublication(tab, reason: reason)
            ?? .ready
    }

    func warmInitialDocumentNativeMessaging(profileID: UUID) async {
        guard lifetime.isEnabled else { return }
        await lifetime.browserRuntimeIfNeededForNormalTab()?.initialDocument
            .warmNativeMessaging(profileID: profileID)
    }

    func needsInitialDocumentExtensionContextLoad(profileID: UUID) -> Bool {
        guard lifetime.isEnabled else { return false }
        return lifetime.browserRuntimeIfNeededForNormalTab()?.initialDocument
            .needsInitialContextLoad(profileID: profileID)
            ?? false
    }

    func consumeRecentlyOpenedExtensionTabRequest(for url: URL) -> Bool {
        lifetime.loadedBrowserRuntimeIfEnabled()?.interaction
            .consumeRecentRequest(for: url) ?? false
    }

    func registerExtensionCreatedTab(_ tab: Tab, reason: String) {
        lifetime.browserRuntimeIfNeededForNormalTab()?.preparation
            .registerCreatedTab(tab, reason: reason)
    }

    func prepareInitialTabPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> InitialTabExtensionPreparation {
        lifetime.loadedBrowserRuntimeIfEnabled()?.preparation
            .prepareInitialPublication(
                window: window,
                tab: tab,
                webView: webView,
                reason: reason
            ) ?? .notParticipating
    }

    func cancelNativeMessagingSessions(reason: String) {
        lifetime.residentBrowserRuntime()?.initialDocument
            .cancelNativeMessaging(reason: reason)
    }

    func loadedAuxiliaryWindowIntegration() -> AuxiliaryWindowExtensionIntegration? {
        lifetime.loadedBrowserRuntimeIfEnabled()?.initialDocument
            .auxiliaryIntegration()
    }
}
