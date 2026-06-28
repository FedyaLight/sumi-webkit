//
//  WebViewAssignmentRebuildOwner.swift
//  Sumi
//
//  Owns normal-tab WebView assignment and live rebuild sequencing.
//

import Foundation
import WebKit

@MainActor
final class WebViewAssignmentRebuildOwner {
    typealias RegisterTrackedWebView = (WKWebView, UUID, UUID) -> Void
    typealias UnregisterTrackedWebViewSlot = (TrackedWebViewOwner, WKWebView?) -> WKWebView?
    typealias ContainerRemoval = (WKWebView) -> Void
    typealias ProtectedWebViewCheck = (WKWebView) -> Bool
    typealias ProtectedRebuildDeferral = (WKWebView, UUID, UUID?) -> Void
    typealias PrimaryCandidateResolver = (UUID, BrowserManager?) -> (owner: TrackedWebViewOwner, webView: WKWebView)?
    typealias TabActivationNotifier = (Tab, UUID) -> Void

    struct Runtime {
        let webViewRegistry: WindowWebViewRegistry
        let browserManager: BrowserManager?
        let registerTrackedWebView: RegisterTrackedWebView
        let unregisterTrackedWebViewSlot: UnregisterTrackedWebViewSlot
        let removeFromContainers: ContainerRemoval
        let isWebViewProtectedFromCompositorMutation: ProtectedWebViewCheck
        let deferProtectedRebuild: ProtectedRebuildDeferral
        let primaryCandidate: PrimaryCandidateResolver
        let notifyTabActivatedIfCurrent: TabActivationNotifier
    }

    private let creationPlanningOwner = WebViewCreationPlanningOwner()

    func getOrCreateWebView(
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        switch creationPlanningOwner.creationPlan(
            for: tab,
            in: windowId,
            browserManager: runtime.browserManager,
            existingWebView: runtime.webViewRegistry.webView(for: tab.id, in: windowId),
            windowWebViews: runtime.webViewRegistry.windowWebViews(for: tab.id)
        ) {
        case .useExisting(let existing):
            return existing
        case .adoptExistingPrimary(let adoptedWebView):
            adoptExistingPrimaryWebView(adoptedWebView, for: tab, in: windowId, runtime: runtime)
            return adoptedWebView
        case .deferForInitialDocumentWarmup(let deferral):
            creationPlanningOwner.startInitialDocumentWarmupIfNeeded(deferral)
            return nil
        case .createPrimary:
            return createPrimaryWebView(for: tab, in: windowId, runtime: runtime)
        case .createClone(let primaryWindowId):
            return createCloneWebView(
                for: tab,
                in: windowId,
                primaryWindowId: primaryWindowId,
                runtime: runtime
            )
        }
    }

    func refreshPrimaryTrackedWebView(
        for tab: Tab,
        browserManager: BrowserManager?,
        runtime: Runtime
    ) {
        guard let replacement = runtime.primaryCandidate(tab.id, browserManager) else {
            if tab._webView != nil {
                tab._webView = nil
            }
            if tab.primaryWindowId != nil {
                tab.primaryWindowId = nil
            }
            return
        }

        if tab._webView !== replacement.webView || tab.primaryWindowId != replacement.owner.windowID {
            tab.assignWebViewToWindow(replacement.webView, windowId: replacement.owner.windowID)
        }
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID? = nil,
        load url: URL? = nil,
        runtime: Runtime
    ) {
        let trackedWindowIds = Set(runtime.webViewRegistry.windowIDs(for: tab.id))
        var targetWindowIds = trackedWindowIds

        if let primaryWindowId = tab.primaryWindowId {
            targetWindowIds.insert(primaryWindowId)
        }
        if let liveWindowIds = tab.browserManager?.windowRegistry?.windows.keys {
            targetWindowIds.formIntersection(liveWindowIds)
        }

        guard targetWindowIds.isEmpty == false else { return }

        let targetURL = url ?? tab.existingWebView?.url ?? tab.url
        let preferredPrimaryWindowIdCandidate: UUID?
        if let preferredPrimaryWindowId,
           targetWindowIds.contains(preferredPrimaryWindowId) {
            preferredPrimaryWindowIdCandidate = preferredPrimaryWindowId
        } else {
            preferredPrimaryWindowIdCandidate = nil
        }
        let existingPrimaryWindowIdCandidate: UUID?
        if let existingPrimaryWindowId = tab.primaryWindowId,
           targetWindowIds.contains(existingPrimaryWindowId) {
            existingPrimaryWindowIdCandidate = existingPrimaryWindowId
        } else {
            existingPrimaryWindowIdCandidate = nil
        }
        let primaryWindowId = preferredPrimaryWindowIdCandidate
            ?? existingPrimaryWindowIdCandidate
            ?? targetWindowIds.sorted { $0.uuidString < $1.uuidString }.first

        guard let primaryWindowId else { return }

        let protectedCandidateWebViews = Array(runtime.webViewRegistry.windowWebViews(for: tab.id).values)
            + [tab.assignedWebView, tab.existingWebView].compactMap { $0 }
        if protectedCandidateWebViews.contains(where: runtime.isWebViewProtectedFromCompositorMutation) {
            let deferredWebViews = protectedCandidateWebViews.filter(runtime.isWebViewProtectedFromCompositorMutation)
            for protectedWebView in deferredWebViews {
                runtime.deferProtectedRebuild(
                    protectedWebView,
                    tab.id,
                    preferredPrimaryWindowId
                )
            }
            return
        }

        let oldEntries = runtime.webViewRegistry.windowWebViews(for: tab.id)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView?) {
            guard let webView else { return }
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (windowId, webView) in oldEntries {
            runtime.removeFromContainers(webView)
            _ = runtime.unregisterTrackedWebViewSlot(
                TrackedWebViewOwner(tabID: tab.id, windowID: windowId),
                webView
            )
            cleanup(webView)
        }
        cleanup(tab.assignedWebView)
        cleanup(tab.existingWebView)

        tab.cancelPendingMainFrameNavigation()
        tab._webView = nil
        tab._existingWebView = nil
        tab.primaryWindowId = nil
        tab.url = targetURL

        guard let recreatedPrimary = tab.ensureWebView() else {
            assertionFailure("Unable to rebuild normal tab WebView without a resolved profile")
            return
        }
        tab.assignWebViewToWindow(recreatedPrimary, windowId: primaryWindowId)
        runtime.registerTrackedWebView(recreatedPrimary, tab.id, primaryWindowId)

        for windowId in targetWindowIds
            .filter({ $0 != primaryWindowId })
            .sorted(by: { $0.uuidString < $1.uuidString }) {
            _ = createCloneWebView(
                for: tab,
                in: windowId,
                primaryWindowId: primaryWindowId,
                runtime: runtime
            )
        }

        for windowId in targetWindowIds {
            guard let windowState = tab.browserManager?.windowRegistry?.windows[windowId] else {
                continue
            }
            tab.browserManager?.refreshCompositor(for: windowState)
        }
    }

    private func createPrimaryWebView(
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        guard let webView = tab.ensureWebView() else {
            assertionFailure("Unable to create normal tab WebView without a resolved profile")
            return nil
        }
        tab.assignWebViewToWindow(webView, windowId: windowId)
        runtime.registerTrackedWebView(webView, tab.id, windowId)
        return webView
    }

    private func createCloneWebView(
        for tab: Tab,
        in windowId: UUID,
        primaryWindowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        guard runtime.webViewRegistry.webView(for: tab.id, in: primaryWindowId) != nil else {
            assertionFailure("Cannot create a clone WebView before the primary WebView is tracked")
            return nil
        }
        guard let newWebView = tab.makeNormalTabWebView(reason: "WebViewCoordinator.createCloneWebView") else {
            assertionFailure("Unable to create normal tab clone WebView without a resolved profile")
            return nil
        }

        runtime.registerTrackedWebView(newWebView, tab.id, windowId)
        loadInitialURLIfNeeded(for: newWebView, tab: tab)
        newWebView.sumiSetAudioMuted(tab.audioState.isMuted)
        runtime.notifyTabActivatedIfCurrent(tab, windowId)
        return newWebView
    }

    private func loadInitialURLIfNeeded(for webView: WKWebView, tab: Tab) {
        if let url = URL(string: tab.url.absoluteString) {
            let performLoad = { [weak tab, weak webView] in
                guard let tab, let webView else { return }
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    guard !resolvedWebView.isLoading, resolvedWebView.url == nil else { return }
                    resolvedWebView.load(URLRequest(url: url))
                }
            }

            let profileId = tab.resolveProfile()?.id ?? tab.profileId
            Task { @MainActor [weak tab] in
                if let controller = webView.configuration.userContentController
                    .sumiNormalTabUserContentController,
                    controller.hasInstalledInitialUserContent == false {
                    await controller.waitForInitialUserContentInstallation()
                }
                if let profileId,
                   let extensionsModule = tab?.browserManager?.extensionsModule {
                    await extensionsModule.ensureInitialDocumentExtensionContextsLoadedIfNeeded(
                        profileId: profileId
                    )
                }
                tab?.registerNormalTabWithExtensionRuntimeIfNeeded(
                    reason: "WebViewCoordinator.loadInitialURLIfNeeded"
                )
                performLoad()
            }
        }
    }

    private func adoptExistingPrimaryWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) {
        runtime.registerTrackedWebView(webView, tab.id, windowId)
        tab.assignWebViewToWindow(webView, windowId: windowId)
    }
}
