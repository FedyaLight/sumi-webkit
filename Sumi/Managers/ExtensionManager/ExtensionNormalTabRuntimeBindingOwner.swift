import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRuntimeBindingOwner {
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
              let adapter = manager.stableAdapter(for: tab)
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
            manager.extensionRuntimeTrace(
                "didOpenTab deferred because=missingUsableWebView generation=\(manager.extensionLoadGeneration) notifyGeneration=\(manager.tabOpenNotificationGeneration) controller=\(manager.extensionRuntimeControllerDescription(controller)) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return false
        }

        manager.extensionRuntimeTrace(
            "didOpenTab start generation=\(manager.extensionLoadGeneration) notifyGeneration=\(manager.tabOpenNotificationGeneration) controller=\(manager.extensionRuntimeControllerDescription(controller)) \(manager.extensionRuntimeTabDescription(tab)) adapter=\(manager.extensionRuntimeObjectDescription(adapter))"
        )
        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration =
            manager.extensionContextBindingGeneration(for: profileId)
        tab.extensionRuntimeOpenNotifiedWithLoadedContexts = true
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
        manager.extensionRuntimeTrace(
            "didOpenTab complete generation=\(manager.extensionLoadGeneration) notifyGeneration=\(manager.tabOpenNotificationGeneration) \(manager.extensionRuntimeTabDescription(tab))"
        )
        return true
    }

    func notifyTabOpenedIfNeeded(_ tab: Tab, reason: String = #function) {
        guard let manager else { return }
        let generation = manager.tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard manager.extensionsLoaded else {
            manager.extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=extensionsNotLoaded generation=\(manager.extensionLoadGeneration) notifyGeneration=\(manager.tabOpenNotificationGeneration) lastNotified=\(tab.lastExtensionOpenNotificationGeneration) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            manager.extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=tabNotEligible generation=\(generation) eligibleGeneration=\(tab.extensionRuntimeEligibleGeneration) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard tab.lastExtensionOpenNotificationGeneration != generation else {
            manager.extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=alreadyNotified generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        manager.extensionRuntimeTrace(
            "notifyTabOpenedIfNeeded proceed reason=\(reason) generation=\(generation) lastNotified=\(tab.lastExtensionOpenNotificationGeneration) \(manager.extensionRuntimeTabDescription(tab))"
        )
        guard notifyTabOpened(tab) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedIfNeeded:\(reason)",
                pageURL: tab.url
            )
            manager.extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded aborted reason=\(reason) because=notifyFailed generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.didNotifyOpenToExtensions = true
        tab.lastExtensionOpenNotificationGeneration = generation
        manager.extensionRuntimeTrace(
            "notifyTabOpenedIfNeeded marked reason=\(reason) generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
        )
    }

    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        guard let manager else { return }
        let generation = manager.tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            manager.extensionRuntimeTrace(
                "notifyTabPropertiesChanged skip because=tabNotEligible requested=\(properties.rawValue) generation=\(generation) eligibleGeneration=\(tab.extensionRuntimeEligibleGeneration) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        let coalescedProperties = coalescedTabChangedProperties(
            for: tab,
            requestedProperties: properties
        )
        guard coalescedProperties.isEmpty == false else {
            manager.extensionRuntimeTrace(
                "notifyTabPropertiesChanged skip because=noDiff requested=\(properties.rawValue) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard let controller = manager.extensionController(for: tab),
              let adapter = manager.stableAdapter(for: tab) else { return }
        controller.didChangeTabProperties(coalescedProperties, for: adapter)
        #if DEBUG
            manager.testHooks.didChangeTabProperties?(tab.id, coalescedProperties)
        #endif
    }

    /// WebKit injects manifest `content_scripts` (including CSS) only when `didOpenTab`
    /// precedes the committed document. A controller on the configuration alone is not enough.
    func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool {
        guard let manager else { return false }
        let documentSequence = tab.extensionRuntimeDocumentSequence
        guard documentSequence > 0 else { return false }
        guard let committedURL = tab.extensionRuntimeCommittedMainDocumentURL,
              isExtensionInjectableCommittedURL(committedURL)
        else {
            return false
        }

        if tab.extensionRuntimeOpenNotifiedWithLoadedContexts == false {
            return true
        }

        if let openBinding = tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration,
           let profileId = manager.resolvedProfileId(for: tab),
           openBinding != manager.extensionContextBindingGeneration(for: profileId)
        {
            return true
        }

        for webView in manager.liveWebViews(for: tab)
            where manager.webViewNeedsExtensionRuntimeRebuild(webView, for: tab)
        {
            return true
        }

        guard let openNotifiedDocumentSequence = tab.extensionRuntimeOpenNotifiedDocumentSequence else {
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
            manager.extensionRuntimeTrace(
                "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation skip reason=\(reason) because=extensionsNotLoaded \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }
        guard tab.isEphemeral == false else { return }
        guard isExtensionInjectableCommittedURL(destinationURL) else { return }
        if tab.extensionRuntimeDocumentSequence == 0,
           tab.extensionRuntimeOpenNotifiedDocumentSequence == 0,
           tab.extensionRuntimeOpenNotifiedWithLoadedContexts == true
        {
            return
        }

        tab.lastExtensionOpenNotificationGeneration = 0
        manager.extensionRuntimeTrace(
            "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation proceed reason=\(reason) destination=\(destinationURL.absoluteString) documentSequence=\(tab.extensionRuntimeDocumentSequence) \(manager.extensionRuntimeTabDescription(tab))"
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
           )
        {
            manager.scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                reason: reason
            )
            return
        }

        let shouldCycleTabLifecycle =
            tab.extensionRuntimeOpenNotifiedDocumentSequence != nil
            || tab.extensionRuntimeDocumentSequence > 0
            || tabNeedsExtensionContentScriptRebind(tab)

        if shouldCycleTabLifecycle,
           let controller = manager.extensionController(for: tab),
           let adapter = manager.stableAdapter(for: tab)
        {
            manager.extensionRuntimeTrace(
                "rebindExtensionTabBeforeCommittedNavigation didCloseTab reason=\(reason) \(manager.extensionRuntimeTabDescription(tab))"
            )
            controller.didCloseTab(adapter, windowIsClosing: false)
            #if DEBUG
                manager.testHooks.didCloseTab?(tab.id)
            #endif
            tab.lastExtensionOpenNotificationGeneration = 0
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
        let generation = manager.tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard manager.extensionsLoaded || allowWhenExtensionsNotLoaded else {
            manager.extensionRuntimeTrace(
                "registerTabWithExtensionRuntime skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.extensionRuntimeEligibleGeneration = generation
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
        let generation = manager.tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard manager.extensionsLoaded else {
            manager.extensionRuntimeTrace(
                "markTabEligibleAfterCommittedNavigation skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.extensionRuntimeEligibleGeneration = generation
        manager.ensureExtensionControllerAttachedForTab(tab, reason: reason)
        notifyTabOpenedIfNeeded(tab, reason: reason)
    }

    func isTabEligibleForCurrentExtensionRuntime(_ tab: Tab) -> Bool {
        guard let manager else { return false }
        guard tab.isEphemeral == false else { return false }
        return isTabEligibleForExtensionRuntime(
            tab,
            generation: manager.tabOpenNotificationGeneration
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
            manager.extensionRuntimeTrace(
                "didOpenTab deferred because=noLiveWebView profile=\(profileId.uuidString) \(manager.extensionRuntimeTabDescription(tab))"
            )
            _ = deferOpen("noLiveWebView")
            return false
        }

        guard manager.attachExtensionControllerIfNeeded(to: webView, for: tab) else {
            manager.extensionRuntimeTrace(
                "didOpenTab deferred because=controllerAttachFailed webView=\(manager.extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) \(manager.extensionRuntimeTabDescription(tab))"
            )
            _ = deferOpen("controllerAttachFailed")
            return false
        }

        guard webView.configuration.webExtensionController === controller else {
            manager.extensionRuntimeTrace(
                "didOpenTab deferred because=controllerMismatch webView=\(manager.extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) \(manager.extensionRuntimeTabDescription(tab))"
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
            if resolvedURL?.absoluteString != tab.extensionRuntimeLastReportedURL?.absoluteString {
                changedProperties.insert(.URL)
                tab.extensionRuntimeLastReportedURL = resolvedURL
            }
        }

        if requestedProperties.contains(.loading) {
            let isLoadingComplete = !tab.isLoading
            if tab.extensionRuntimeLastReportedLoadingComplete != isLoadingComplete {
                changedProperties.insert(.loading)
                tab.extensionRuntimeLastReportedLoadingComplete = isLoadingComplete
            }
        }

        if requestedProperties.contains(.title) {
            let title = tab.name.isEmpty ? nil : tab.name
            if tab.extensionRuntimeLastReportedTitle != title {
                changedProperties.insert(.title)
                tab.extensionRuntimeLastReportedTitle = title
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
        tab.extensionRuntimeEligibleGeneration == generation
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
