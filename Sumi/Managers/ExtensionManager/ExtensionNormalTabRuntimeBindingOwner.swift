import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRuntimeBindingOwner: ExtensionTabOpenNotifying {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    @discardableResult
    func notifyTabOpened(_ tab: Tab) -> Bool {
        guard let manager else { return false }

        func deferOpen(_ reason: String) -> Bool {
            #if DEBUG
                manager.testHooks.didDeferOpenTab?(tab.id, reason)
            #endif
            return false
        }

        guard let controller = manager.extensionController(for: tab),
              let adapter = manager.adapterResolutionOwner.stableAdapter(for: tab)
        else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingAdapterOrController",
                pageURL: tab.url
            )
            return deferOpen("missingAdapterOrController")
        }

        guard let profileId = manager.resolvedProfileId(for: tab) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingProfile",
                pageURL: tab.url
            )
            return deferOpen("missingProfile")
        }

        let contextsReady = manager.profileNeedsInitialDocumentExtensionContextLoad(
            profileId: profileId
        ) == false
        guard contextsReady else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedInitialDocumentContextsNotLoaded",
                pageURL: tab.url
            )
            manager.scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                reason: "notifyTabOpened"
            )
            return deferOpen("initialDocumentContextsNotLoaded")
        }

        guard tabHasUsableWebViewForExtensionOpenNotification(
            tab,
            controller: controller,
            profileId: profileId,
            deferOpen: deferOpen
        ) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingUsableWebView",
                pageURL: tab.url
            )
            manager.runtimeDiagnostics.trace(
                "didOpenTab deferred because=missingUsableWebView generation=\(manager.runtimeSession.extensionLoadGeneration) notifyGeneration=\(manager.runtimeSession.tabOpenNotificationGeneration) controller=\(ExtensionRuntimeDiagnostics.objectDescription(controller)) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return false
        }

        // A lazily restored Tab can materialize after its window entered the
        // registry. Reconcile the exact window projection first so WebKit can
        // never observe didOpenTab before didOpenWindow.
        guard manager.browserRuntimeBridgeOwner.prepareTabOpen(tab) else {
            return deferOpen("windowProjectionUnavailable")
        }

        manager.runtimeDiagnostics.trace(
            "didOpenTab start generation=\(manager.runtimeSession.extensionLoadGeneration) notifyGeneration=\(manager.runtimeSession.tabOpenNotificationGeneration) controller=\(ExtensionRuntimeDiagnostics.objectDescription(controller)) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager)) adapter=\(ExtensionRuntimeDiagnostics.objectDescription(adapter))"
        )
        tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration: manager.extensionContextBindingGeneration(for: profileId),
            contextReadiness: .loaded
        )
        // Reserve the generation before the external callback. WebKit may
        // synchronously re-enter registration from didOpenTab.
        tab.extensionPageRuntimeOwner.markDidOpenTab(
            generation: manager.runtimeSession.tabOpenNotificationGeneration
        )
        controller.didOpenTab(adapter)
        #if DEBUG
            manager.testHooks.didOpenTab?(tab.id)
        #endif
        SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
            injected: true,
            extensionId: nil,
            reason: "didOpenTab",
            pageURL: tab.url
        )
        manager.runtimeDiagnostics.trace(
            "didOpenTab complete generation=\(manager.runtimeSession.extensionLoadGeneration) notifyGeneration=\(manager.runtimeSession.tabOpenNotificationGeneration) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
        )
        return true
    }

    func notifyTabOpenedIfNeeded(_ tab: Tab, reason: String = #function) {
        guard let manager else { return }
        let generation = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)

        guard manager.extensionsLoaded else {
            manager.runtimeDiagnostics.trace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=extensionsNotLoaded generation=\(manager.runtimeSession.extensionLoadGeneration) notifyGeneration=\(manager.runtimeSession.tabOpenNotificationGeneration) lastNotified=\(tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration()) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            manager.runtimeDiagnostics.trace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=tabNotEligible generation=\(generation) eligibleGeneration=\(tab.extensionPageRuntimeOwner.currentEligibleGeneration()) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        guard tab.extensionPageRuntimeOwner.hasDidOpenTabNotification(for: generation) == false else {
            manager.runtimeDiagnostics.trace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=alreadyNotified generation=\(generation) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        manager.runtimeDiagnostics.trace(
            "notifyTabOpenedIfNeeded proceed reason=\(reason) generation=\(generation) lastNotified=\(tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration()) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
        )
        guard notifyTabOpened(tab) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedIfNeeded:\(reason)",
                pageURL: tab.url
            )
            manager.runtimeDiagnostics.trace(
                "notifyTabOpenedIfNeeded aborted reason=\(reason) because=notifyFailed generation=\(generation) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        manager.runtimeDiagnostics.trace(
            "notifyTabOpenedIfNeeded marked reason=\(reason) generation=\(generation) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
        )
    }

    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        guard let manager else { return }
        let generation = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            manager.runtimeDiagnostics.trace(
                "notifyTabPropertiesChanged skip because=tabNotEligible requested=\(properties.rawValue) generation=\(generation) eligibleGeneration=\(tab.extensionPageRuntimeOwner.currentEligibleGeneration()) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        let coalescedProperties = coalescedTabChangedProperties(
            for: tab,
            requestedProperties: properties
        )
        guard coalescedProperties.isEmpty == false else {
            manager.runtimeDiagnostics.trace(
                "notifyTabPropertiesChanged skip because=noDiff requested=\(properties.rawValue) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        guard let controller = manager.extensionController(for: tab),
              let adapter = manager.adapterResolutionOwner.stableAdapter(for: tab) else { return }
        controller.didChangeTabProperties(coalescedProperties, for: adapter)
        #if DEBUG
            manager.testHooks.didChangeTabProperties?(tab.id, coalescedProperties)
        #endif
    }

    /// WebKit injects manifest `content_scripts` (including CSS) only when `didOpenTab`
    /// precedes the committed document. A controller on the configuration alone is not enough.
    func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool {
        guard let manager else { return false }
        let documentBinding = tab.extensionPageRuntimeOwner.documentBindingSnapshot()
        let documentSequence = documentBinding.documentSequence
        guard documentSequence > 0 else { return false }
        guard let committedURL = documentBinding.committedMainDocumentURL,
              isExtensionInjectableCommittedURL(committedURL)
        else {
            return false
        }

        if documentBinding.openNotifiedContextReadiness == .missing {
            return true
        }

        if let openBinding = documentBinding.openNotifiedContextBindingGeneration,
           let profileId = manager.resolvedProfileId(for: tab),
           openBinding != manager.extensionContextBindingGeneration(for: profileId) {
            return true
        }

        for webView in manager.liveWebViews(for: tab)
            where manager.webViewNeedsExtensionRuntimeRebuild(webView, for: tab) {
            return true
        }

        guard let openNotifiedDocumentSequence = documentBinding.openNotifiedDocumentSequence else {
            return true
        }

        return openNotifiedDocumentSequence != documentSequence - 1
    }

    /// Re-binds extension runtime when the user interacts with a page whose committed
    /// document never received a pre-commit `didOpenTab` notification.
    func reconcileExtensionRuntimeOnUserGestureIfNeeded(
        _ tab: Tab,
        reason: String = #function
    ) {
        guard let manager else { return }
        guard manager.extensionsLoaded else { return }
        guard tab.isEphemeral == false else { return }
        guard tabNeedsExtensionContentScriptRebind(tab) else { return }
        registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    /// Delivers a fresh `didCloseTab`/`didOpenTab` pair before the next main-frame document
    /// commits so WebKit injects manifest `content_scripts` (including CSS) on reload and other
    /// regular navigations. Generation-based deduplication alone is insufficient because WebKit
    /// ignores a second `didOpenTab` on an already-open tab adapter until `didCloseTab` runs.
    func prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String = #function
    ) {
        guard let manager else { return }
        guard manager.extensionsLoaded else {
            manager.runtimeDiagnostics.trace(
                "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation skip reason=\(reason) because=extensionsNotLoaded \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }
        guard tab.isEphemeral == false else { return }
        guard isExtensionInjectableCommittedURL(destinationURL) else { return }
        if tab.extensionPageRuntimeOwner.shouldSkipPreCommitRebindForInitialDocument() {
            return
        }

        tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        let documentSequence = tab.extensionPageRuntimeOwner.documentBindingSnapshot().documentSequence
        manager.runtimeDiagnostics.trace(
            "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation proceed reason=\(reason) destination=\(destinationURL.absoluteString) documentSequence=\(documentSequence) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
        )
        rebindExtensionTabBeforeCommittedNavigation(
            tab,
            reason: reason
        )
    }

    /// Re-binds a live tab to WebKit immediately before a committed navigation so manifest
    /// `content_scripts` can inject on the incoming document.
    func rebindExtensionTabBeforeCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        guard let manager else { return }
        manager.ensureExtensionControllerAttachedForTab(tab, reason: reason)

        if let profileId = manager.resolvedProfileId(for: tab),
           manager.profileNeedsInitialDocumentExtensionContextLoad(
               profileId: profileId
           ) {
            manager.scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                reason: reason
            )
            return
        }

        let shouldCycleTabLifecycle =
            tab.extensionPageRuntimeOwner.hasDocumentBindingForLifecycleRebind()
            || tabNeedsExtensionContentScriptRebind(tab)

        if shouldCycleTabLifecycle,
           let controller = manager.extensionController(for: tab),
           let adapter = manager.adapterResolutionOwner.stableAdapter(for: tab) {
            manager.runtimeDiagnostics.trace(
                "rebindExtensionTabBeforeCommittedNavigation didCloseTab reason=\(reason) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            controller.didCloseTab(adapter, windowIsClosing: false)
            #if DEBUG
                manager.testHooks.didCloseTab?(tab.id)
            #endif
            tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        }

        registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    func registerTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String = #function,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard let manager else { return }
        let generation = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)

        guard manager.extensionsLoaded || allowWhenExtensionsNotLoaded else {
            manager.runtimeDiagnostics.trace(
                "registerTabWithExtensionRuntime skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        manager.ensureExtensionControllerAttachedForTab(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
        notifyTabOpenedIfNeeded(tab, reason: reason)
    }

    func markTabEligibleAfterCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        guard let manager else { return }
        let generation = manager.runtimeSession.tabOpenNotificationGeneration
        tab.extensionPageRuntimeOwner.prepareGeneration(generation)

        guard manager.extensionsLoaded else {
            manager.runtimeDiagnostics.trace(
                "markTabEligibleAfterCommittedNavigation skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            return
        }

        tab.extensionPageRuntimeOwner.markEligible(for: generation)
        manager.ensureExtensionControllerAttachedForTab(tab, reason: reason)
        notifyTabOpenedIfNeeded(tab, reason: reason)
    }

    func isTabEligibleForCurrentExtensionRuntime(_ tab: Tab) -> Bool {
        guard let manager else { return false }
        guard tab.isEphemeral == false else { return false }
        return isTabEligibleForExtensionRuntime(
            tab,
            generation: manager.runtimeSession.tabOpenNotificationGeneration
        )
    }

    private func tabHasUsableWebViewForExtensionOpenNotification(
        _ tab: Tab,
        controller: WKWebExtensionController,
        profileId: UUID,
        deferOpen: (String) -> Bool
    ) -> Bool {
        guard let manager else { return false }
        guard let webView = manager.resolvedLiveWebView(for: tab) else {
            manager.runtimeDiagnostics.trace(
                "didOpenTab deferred because=noLiveWebView profile=\(profileId.uuidString) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            _ = deferOpen("noLiveWebView")
            return false
        }

        guard manager.attachExtensionControllerIfNeeded(to: webView, for: tab) else {
            manager.runtimeDiagnostics.trace(
                "didOpenTab deferred because=controllerAttachFailed webView=\(ExtensionRuntimeDiagnostics.objectDescription(webView)) profile=\(profileId.uuidString) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            _ = deferOpen("controllerAttachFailed")
            return false
        }

        guard webView.configuration.webExtensionController === controller else {
            manager.runtimeDiagnostics.trace(
                "didOpenTab deferred because=controllerMismatch webView=\(ExtensionRuntimeDiagnostics.objectDescription(webView)) profile=\(profileId.uuidString) \(manager.runtimeDiagnostics.tabDescription(tab, manager: manager))"
            )
            _ = deferOpen("controllerMismatch")
            return false
        }

        return true
    }

    private func coalescedTabChangedProperties(
        for tab: Tab,
        requestedProperties: WKWebExtension.TabChangedProperties
    ) -> WKWebExtension.TabChangedProperties {
        var changedProperties: WKWebExtension.TabChangedProperties = []

        if requestedProperties.contains(.URL) {
            let resolvedURL = resolvedLiveURL(for: tab)
            if tab.extensionPageRuntimeOwner.recordReportedURLIfChanged(resolvedURL) {
                changedProperties.insert(.URL)
            }
        }

        if requestedProperties.contains(.loading) {
            let isLoadingComplete = !tab.isLoading
            if tab.extensionPageRuntimeOwner.recordReportedLoadingCompleteIfChanged(isLoadingComplete) {
                changedProperties.insert(.loading)
            }
        }

        if requestedProperties.contains(.title) {
            let title = tab.name.isEmpty ? nil : tab.name
            if tab.extensionPageRuntimeOwner.recordReportedTitleIfChanged(title) {
                changedProperties.insert(.title)
            }
        }

        return changedProperties
    }

    private func resolvedLiveURL(for tab: Tab) -> URL? {
        guard let manager else { return tab.url }
        for webView in manager.liveWebViews(for: tab) {
            if let url = webView.url {
                return url
            }
        }

        return tab.url
    }

    private func isTabEligibleForExtensionRuntime(
        _ tab: Tab,
        generation: UInt64
    ) -> Bool {
        tab.extensionPageRuntimeOwner.isEligible(for: generation)
    }

    private func isExtensionInjectableCommittedURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func notifyTabOpened(_ tab: Tab) -> Bool {
        normalTabRuntimeBindingOwner.notifyTabOpened(tab)
    }

    func notifyTabOpenedIfNeeded(_ tab: Tab, reason: String = #function) {
        normalTabRuntimeBindingOwner.notifyTabOpenedIfNeeded(
            tab,
            reason: reason
        )
    }

    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        normalTabRuntimeBindingOwner.notifyTabPropertiesChanged(
            tab,
            properties: properties
        )
    }

    func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool {
        normalTabRuntimeBindingOwner.tabNeedsExtensionContentScriptRebind(tab)
    }

    func reconcileExtensionRuntimeOnUserGestureIfNeeded(
        _ tab: Tab,
        reason: String = #function
    ) {
        normalTabRuntimeBindingOwner.reconcileExtensionRuntimeOnUserGestureIfNeeded(
            tab,
            reason: reason
        )
    }

    func prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String = #function
    ) {
        normalTabRuntimeBindingOwner
            .prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
                tab,
                destinationURL: destinationURL,
                reason: reason
            )
    }

    func rebindExtensionTabBeforeCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        normalTabRuntimeBindingOwner.rebindExtensionTabBeforeCommittedNavigation(
            tab,
            reason: reason
        )
    }

    func registerTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String = #function,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        normalTabRuntimeBindingOwner.registerTabWithExtensionRuntime(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
    }

    func markTabEligibleAfterCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        normalTabRuntimeBindingOwner.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: reason
        )
    }

    func isTabEligibleForCurrentExtensionRuntime(_ tab: Tab) -> Bool {
        normalTabRuntimeBindingOwner.isTabEligibleForCurrentExtensionRuntime(tab)
    }
}
