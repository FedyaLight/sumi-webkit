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
        lifetime.managerIfNeededForNormalTabRuntime()?.normalTabUserScripts() ?? []
    }

    func prepareWebViewConfiguration(
        _ configuration: WKWebViewConfiguration,
        profileID: UUID?,
        reason: String
    ) {
        lifetime.managerIfNeededForNormalTabRuntime()?
            .prepareWebViewConfigForExtensionRuntime(
                configuration,
                profileId: profileID,
                reason: reason
            )
    }

    func prepareWebView(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        lifetime.managerIfNeededForNormalTabRuntime()?
            .prepareWebViewForExtensionRuntime(
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
        lifetime.managerIfNeededForNormalTabRuntime()?.prepareExtensionPageNavigation(
            tab,
            targetURL: targetURL,
            reason: reason
        ) ?? .notNeeded
    }

    func registerTab(_ tab: Tab, reason: String) {
        lifetime.managerIfNeededForNormalTabRuntime()?.normalTabRegistration.register(
            tab,
            reason: reason
        )
    }

    func reconcileOnUserGesture(_ tab: Tab, reason: String) {
        lifetime.loadedManagerIfEnabled()?.tabLifecycleRebind
            .reconcileOnUserGestureIfNeeded(tab, reason: reason)
    }

    func publishWindow(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        guard let manager = lifetime.loadedManagerIfEnabled(),
              manager.extensionsLoaded
        else {
            return .notParticipating
        }
        guard manager.runtimePublicationGate.admitStructuralBrowserEvent(),
              let publication = manager.normalWindowLifecycle.publication(for: windowState)
        else {
            return .suppressed
        }
        return .published(publication)
    }

    func notifyWindowOpened(_ windowState: BrowserWindowState) -> Bool {
        if case .published = publishWindow(windowState) {
            return true
        }
        return false
    }

    func notifyWindowClosed(_ windowState: BrowserWindowState) {
        guard let manager = lifetime.loadedManagerIfEnabled(),
              manager.runtimePublicationGate.admitStructuralBrowserEvent()
        else { return }
        manager.normalWindowLifecycle.closed(windowState)
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        lifetime.loadedManagerIfEnabled()?.focusPublishedWindow(windowState)
    }

    func switchProfile(_ profile: Profile) {
        lifetime.loadedManagerIfEnabled()?.profileRuntimeTransition.switchProfile(
            profileID: profile.id
        )
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let manager = lifetime.loadedManagerIfEnabled(),
              manager.runtimePublicationGate.acceptsBrowserEvents
        else { return }
        manager.normalTabActivation.activate(newTab, previous: previous)
    }

    func notifyTabClosed(_ tab: Tab) {
        guard let manager = lifetime.loadedManagerIfEnabled() else { return }
        switch manager.runtimePublicationGate.exactTabCloseDisposition() {
        case .perform:
            manager.normalTabClosure.close(tab)
        case .deferUntilReloadHandoff:
            _ = manager.runtimePublicationReconciler.deferTabClose(tab)
        case .reject:
            break
        }
    }

    func publishTabPropertiesIfResident(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        lifetime.loadedManagerIfEnabled()?.tabPropertyPublisher.publishChange(
            for: tab,
            requested: properties
        )
    }

    func performKeyboardCommand(for event: NSEvent) -> Bool {
        lifetime.loadedManagerIfEnabled()?
            .performExtensionKeyboardCommand(for: event) ?? false
    }

    func pageContextMenuItems(for tab: Tab) -> [NSMenuItem] {
        lifetime.loadedManagerIfEnabled()?.pageContextMenuItems(for: tab) ?? []
    }

    func admitTabAfterCommittedNavigation(_ tab: Tab, reason: String) {
        lifetime.loadedManagerIfEnabled()?.normalTabRegistration
            .markEligibleAfterCommittedNavigation(tab, reason: reason)
    }

    func prepareBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        lifetime.loadedManagerIfEnabled()?.tabLifecycleRebind
            .prepareBeforeCommittedMainFrameNavigation(
                tab,
                destinationURL: destinationURL,
                reason: reason
            )
    }

    func ensureInitialExtensionContexts(profileID: UUID) async {
        guard lifetime.isEnabled else { return }
        await lifetime.managerIfNeededForNormalTabRuntime()?
            .ensureInitialExtensionContextsLoaded(for: profileID)
    }

    func needsInitialDocumentExtensionContextLoad(profileID: UUID) -> Bool {
        guard lifetime.isEnabled else { return false }
        return lifetime.managerIfNeededForNormalTabRuntime()?
            .profileNeedsInitialDocumentExtensionContextLoad(profileId: profileID)
            ?? false
    }

    func consumeRecentlyOpenedExtensionTabRequest(for url: URL) -> Bool {
        lifetime.loadedManagerIfEnabled()?.recentExtensionTabRequests.consume(url) ?? false
    }

    func registerExtensionCreatedTab(_ tab: Tab, reason: String) {
        guard let manager = lifetime.managerIfNeededForNormalTabRuntime() else { return }
        manager.extensionCreatedTabRegistrar.register(
            tab,
            runtime: manager.runtime,
            reason: reason
        )
    }

    func prepareInitialTabPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> InitialTabExtensionPreparation {
        guard window.isIncognito == false, tab.isEphemeral == false else {
            return .privateWindow
        }
        guard let manager = lifetime.loadedManagerIfEnabled(),
              manager.extensionsLoaded
        else {
            return .notParticipating
        }
        guard let windowProfileID = manager.resolvedProfileId(for: window),
              let tabProfileID = manager.resolvedProfileId(for: tab)
        else {
            return .rejected
        }
        guard windowProfileID == tabProfileID else {
            return .suppressed
        }
        guard manager.existingTabControllers.existingController(for: tab) != nil else {
            return .notParticipating
        }
        guard manager.profileNeedsInitialDocumentExtensionContextLoad(
            profileId: tabProfileID
        ) == false else {
            return .suppressed
        }
        guard let windowRegistry = manager.extensionWindowQuery,
              let receipt = manager.initialTabPublicationPreparer.prepare(
                  window: window,
                  tab: tab,
                  webView: webView,
                  runtime: manager.runtime,
                  windowRegistry: windowRegistry,
                  reason: reason
              )
        else {
            return .rejected
        }
        return .prepared(receipt)
    }

    func cancelNativeMessagingSessions(reason: String) {
        guard let manager = lifetime.residentManager() else { return }
        manager.runtimeDiagnostics.trace(
            "nativeMessagingCancelSessions reason=\(reason) "
                + "count=\(manager.nativeMessagingPortRegistry.count)"
        )
        manager.nativeMessagingPortRegistry.disconnectAll()
        manager.loadedNativeMessagingRelayOwner?.loadedRelay?.clearAllLoopGuardState()
    }

    func loadedAuxiliaryWindowIntegration() -> AuxiliaryWindowExtensionIntegration? {
        lifetime.loadedManagerIfEnabled()?.auxiliaryWindowIntegration()
    }
}
