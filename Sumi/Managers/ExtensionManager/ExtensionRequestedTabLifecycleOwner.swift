import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabLifecycleOwner {
    private struct Target {
        let window: BrowserWindowState?
        let space: Space?
    }

    private nonisolated static let recentTabOpenRequestTTL: TimeInterval = 2

    private var recentOpenRequests = BoundedRecentDateTracker(
        ttl: ExtensionRequestedTabLifecycleOwner.recentTabOpenRequestTTL,
        maxKeys: 128,
        maxDatesPerKey: 4
    )

    private nonisolated static func recentTabOpenRequestKey(
        for url: URL?
    ) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url.absoluteString
    }

    func consumeRecentlyOpenedTabRequest(for url: URL) -> Bool {
        guard let key = Self.recentTabOpenRequestKey(for: url) else {
            return false
        }

        return recentOpenRequests.consume(key: key)
    }

    func recordRecentlyOpenedTabRequest(for url: URL?) {
        guard let key = Self.recentTabOpenRequestKey(for: url) else {
            return
        }
        recentOpenRequests.record(key: key)
    }

    func removeAllRecentlyOpenedTabRequests() {
        recentOpenRequests.removeAll()
    }

    func loadURL(
        for requestedURL: URL?,
        controller: WKWebExtensionController
    ) -> (url: URL?, context: WKWebExtensionContext?) {
        guard let requestedURL else {
            return (nil, nil)
        }

        guard ExtensionUtils.isExtensionOwnedURL(requestedURL) else {
            return (requestedURL, nil)
        }
        return (
            requestedURL,
            controller.extensionContext(for: requestedURL)
        )
    }

    @discardableResult
    func prepareInitialLoad(
        url: URL?,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        manager: ExtensionManager
    ) async throws -> UUID? {
        let resolvedExtensionLoad = loadURL(
            for: url,
            controller: controller
        )
        guard shouldPreloadContentScriptContexts(
            loadURL: resolvedExtensionLoad.url,
            webExtensionContextOverride: resolvedExtensionLoad.context
        ) else {
            return nil
        }

        let target = try requestedTabTarget(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext,
            manager: manager
        )
        return await prepareContentScriptContextsForInitialLoad(
            loadURL: resolvedExtensionLoad.url,
            webExtensionContextOverride: resolvedExtensionLoad.context,
            targetWindow: target.window,
            targetSpace: target.space,
            controller: controller,
            manager: manager
        )
    }

    @discardableResult
    func prepareContentScriptContextsForInitialLoad(
        loadURL: URL?,
        webExtensionContextOverride: WKWebExtensionContext?,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?,
        controller: WKWebExtensionController,
        manager: ExtensionManager
    ) async -> UUID? {
        guard shouldPreloadContentScriptContexts(
            loadURL: loadURL,
            webExtensionContextOverride: webExtensionContextOverride
        ) else {
            return nil
        }

        guard let profileId =
            targetSpace?.profileId
                ?? targetWindow.flatMap(manager.resolvedProfileId(for:))
                ?? manager.profileId(for: controller)
                ?? manager.currentProfileId
                ?? manager.browserManager?.currentProfile?.id
        else {
            return nil
        }

        await manager.ensureContentScriptContextsLoaded(for: profileId)
        return profileId
    }

    @discardableResult
    func openTab(
        url: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        reason: String,
        manager: ExtensionManager
    ) throws -> Tab {
        guard let browserContext = manager.browserBridgeContext else {
            throw ExtensionManagerCallbackError.requestedTabBrowserManagerUnavailable.nsError()
        }

        let target = try requestedTabTarget(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext,
            manager: manager
        )
        let targetWindow = target.window
        let targetSpace = target.space

        let resolvedExtensionLoad = loadURL(
            for: url,
            controller: controller
        )
        let webExtensionContextOverride = resolvedExtensionLoad.context
        let shouldUseTransientInternalTab = shouldOpenAsTransientInternalExtensionTab(
            loadURL: resolvedExtensionLoad.url,
            shouldBeActive: shouldBeActive,
            shouldBePinned: shouldBePinned,
            webExtensionContextOverride: webExtensionContextOverride
        )
        let diagnosticProfileId =
            targetSpace?.profileId
                ?? targetWindow.flatMap(manager.resolvedProfileId(for:))
                ?? extensionContext.flatMap { manager.profileId(for: $0) }
                ?? manager.profileId(for: controller)
                ?? manager.currentProfileId

        let newTab: Tab
        if shouldUseTransientInternalTab, let loadURL = resolvedExtensionLoad.url {
            newTab = browserContext.createTransientExtensionTab(
                url: loadURL,
                in: targetSpace,
                webExtensionContextOverride: webExtensionContextOverride
            )
        } else if let loadURL = resolvedExtensionLoad.url {
            recordRecentlyOpenedTabRequest(for: url)
            newTab = browserContext.createExtensionTab(
                url: loadURL,
                in: targetSpace,
                activate: shouldBeActive,
                webExtensionContextOverride: webExtensionContextOverride
            )
        } else {
            newTab = browserContext.createExtensionTab(
                url: nil,
                in: targetSpace,
                activate: shouldBeActive,
                webExtensionContextOverride: webExtensionContextOverride
            )
        }

        if shouldBePinned {
            browserContext.pinExtensionTab(
                newTab,
                targetWindow: targetWindow,
                targetSpace: targetSpace
            )
        }

        materializeNormalTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            targetWindow: targetWindow,
            manager: manager
        )
        if shouldBeActive, let targetWindow {
            browserContext.selectExtensionTab(newTab, in: targetWindow)
        }

        registerCreatedTabWithExtensionRuntime(newTab, reason: reason, manager: manager)
        materializeExtensionOwnedTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            hasWindowSelection: targetWindow != nil
        )
        SafariExtensionPermissionLifecycleDiagnostics.logTabBinding(
            SafariExtensionTabBindingSnapshot(
                route: shouldUseTransientInternalTab ? .extensionInternal : .normalBrowserTab,
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                    manager.resolvedProfileId(for: newTab) ?? diagnosticProfileId
                ),
                tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(newTab.id),
                dataStoreMatched: nil,
                controllerMatched: nil,
                tabAdapterCreated: manager.stableAdapter(for: newTab) != nil,
                didOpenTabTiming: newTab.lastExtensionOpenNotificationGeneration > 0
                    ? .beforeNavigation : .deferred,
                firstNavigationHost: SafariExtensionPermissionLifecycleDiagnostics.host(
                    from: resolvedExtensionLoad.url
                ),
                firstCommitHost: nil
            )
        )
        return newTab
    }

    func materializeNormalTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        targetWindow: BrowserWindowState?,
        manager: ExtensionManager
    ) {
        guard isActive,
              tab.webExtensionContextOverride == nil,
              tab.requiresPrimaryWebView
        else {
            return
        }

        if let targetWindow {
            manager.browserBridgeContext?.materializeVisibleExtensionTabWebViewIfNeeded(
                tab,
                in: targetWindow
            )
        }
        if tab.isUnloaded {
            tab.loadWebViewIfNeeded()
        }
        prepareNormalTabWebViewForOpenNotification(
            tab,
            targetWindow: targetWindow,
            manager: manager
        )
    }

    func registerCreatedTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String,
        manager: ExtensionManager
    ) {
        let generation = manager.tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)
        tab.extensionRuntimeEligibleGeneration = generation

        guard tab.lastExtensionOpenNotificationGeneration != generation else {
            manager.extensionRuntimeTrace(
                "registerExtensionCreatedTab skip reason=\(reason) because=alreadyNotified generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard manager.notifyTabOpened(tab) else {
            manager.extensionRuntimeTrace(
                "registerExtensionCreatedTab skip reason=\(reason) because=notifyFailed generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence
        if let profileId = manager.resolvedProfileId(for: tab) {
            tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration =
                manager.extensionContextBindingGeneration(for: profileId)
            tab.extensionRuntimeOpenNotifiedWithLoadedContexts =
                manager.profileHasLoadedContentScriptContexts(profileId: profileId)
        }
        tab.didNotifyOpenToExtensions = true
        tab.lastExtensionOpenNotificationGeneration = generation
        manager.extensionRuntimeTrace(
            "registerExtensionCreatedTab marked reason=\(reason) generation=\(generation) \(manager.extensionRuntimeTabDescription(tab))"
        )
    }

    private func requestedTabTarget(
        requestedWindow: (any WKWebExtensionWindow)?,
        extensionContext: WKWebExtensionContext?,
        manager: ExtensionManager
    ) throws -> Target {
        guard let browserContext = manager.browserBridgeContext else {
            throw ExtensionManagerCallbackError.requestedTabBrowserManagerUnavailable.nsError()
        }

        if let miniWindowAdapter = requestedWindow as? ExtensionMiniWindowAdapter,
           let session = browserContext.auxiliaryWindowSession(for: miniWindowAdapter.sessionId) {
            return Target(
                window: requestedNormalWindow(
                    for: session.tab,
                    extensionContext: extensionContext,
                    manager: manager
                ),
                space: requestedTargetSpace(for: session.tab, manager: manager)
            )
        }

        if requestedWindow == nil,
           let extensionContext,
           let ownerExtensionID = manager.extensionID(for: extensionContext),
           let profileId = manager.profileId(for: extensionContext),
           let miniWindowAdapter = manager.extensionMiniWindowAdapters(
               ownerExtensionID: ownerExtensionID,
               profileId: profileId
           ).first,
           let session = browserContext.auxiliaryWindowSession(for: miniWindowAdapter.sessionId) {
            return Target(
                window: requestedNormalWindow(
                    for: session.tab,
                    extensionContext: extensionContext,
                    manager: manager
                ),
                space: requestedTargetSpace(for: session.tab, manager: manager)
            )
        }

        let requestedWindowState = (requestedWindow as? ExtensionWindowAdapter)
            .flatMap { browserContext.extensionWindowState(for: $0.windowId) }
        let targetWindow = requestedWindowState ?? browserContext.activeExtensionWindowState
        let targetSpace = browserContext.extensionTargetSpace(for: targetWindow)
        return Target(
            window: targetWindow,
            space: targetSpace
        )
    }

    private func requestedNormalWindow(
        for openerTab: Tab,
        extensionContext: WKWebExtensionContext?,
        manager: ExtensionManager
    ) -> BrowserWindowState? {
        guard let browserContext = manager.browserBridgeContext else { return nil }
        let targetProfileId =
            manager.resolvedProfileId(for: openerTab)
                ?? extensionContext.flatMap { manager.profileId(for: $0) }
                ?? manager.currentProfileId
                ?? manager.browserManager?.currentProfile?.id

        let candidates = [
            browserContext.extensionWindowState(containing: openerTab),
            browserContext.activeExtensionWindowState,
        ]

        return candidates.compactMap { $0 }.first { windowState in
            targetProfileId.map { manager.windowMatchesProfile(windowState, profileId: $0) } ?? true
        }
    }

    private func requestedTargetSpace(
        for tab: Tab,
        manager: ExtensionManager
    ) -> Space? {
        manager.browserBridgeContext?.extensionTargetSpace(for: tab)
    }

    private func shouldPreloadContentScriptContexts(
        loadURL: URL?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Bool {
        guard webExtensionContextOverride == nil,
              let scheme = loadURL?.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }

    private func shouldOpenAsTransientInternalExtensionTab(
        loadURL: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Bool {
        guard shouldBeActive == false,
              shouldBePinned == false,
              webExtensionContextOverride != nil,
              let loadURL
        else {
            return false
        }
        return ExtensionUtils.isExtensionOwnedURL(loadURL)
    }

    private func prepareNormalTabWebViewForOpenNotification(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        manager: ExtensionManager
    ) {
        if let webView = tab.assignedWebView ?? tab.existingWebView {
            manager.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: tab.url,
                reason: "ExtensionManager.extensionRequestedNormalTab"
            )
            if normalTabWebViewIsUsable(webView, for: tab, manager: manager) {
                return
            }
        }

        let replacementReason = "ExtensionManager.extensionRequestedNormalTab.replacement"
        guard let replacementWebView = tab.makeNormalTabWebView(
            reason: replacementReason,
            prepareConfiguration: { [weak manager, weak tab] configuration in
                guard let manager,
                      let tab,
                      let profileId = manager.resolvedProfileId(for: tab)
                else {
                    return
                }
                manager.prepareWebViewConfigurationForExtensionRuntime(
                    configuration,
                    profileId: profileId,
                    reason: "\(replacementReason).configuration"
                )
            }
        ) else {
            return
        }
        manager.prepareWebViewForExtensionRuntime(
            replacementWebView,
            currentURL: tab.url,
            reason: replacementReason
        )
        guard normalTabWebViewIsUsable(replacementWebView, for: tab, manager: manager) else {
            tab.cleanupCloneWebView(replacementWebView)
            return
        }

        let previousWebView = tab.existingWebView
        if let targetWindow {
            tab.assignWebViewToWindow(replacementWebView, windowId: targetWindow.id)
            manager.browserBridgeContext?.assignExtensionWebView(
                replacementWebView,
                to: tab,
                in: targetWindow
            )
        } else {
            tab._webView = replacementWebView
        }
        if let previousWebView, previousWebView !== replacementWebView {
            tab.cleanupCloneWebView(previousWebView)
        }
    }

    private func normalTabWebViewIsUsable(
        _ webView: WKWebView,
        for tab: Tab,
        manager: ExtensionManager
    ) -> Bool {
        guard let expectedController = manager.extensionController(for: tab),
              manager.attachExtensionControllerIfNeeded(to: webView, for: tab)
        else {
            return false
        }
        return webView.configuration.webExtensionController === expectedController
    }

    private func materializeExtensionOwnedTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        hasWindowSelection: Bool
    ) {
        guard tab.webExtensionContextOverride != nil else { return }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) else { return }
        guard tab.isUnloaded else { return }

        if isActive && hasWindowSelection {
            return
        }

        tab.loadWebViewIfNeeded()
    }
}
