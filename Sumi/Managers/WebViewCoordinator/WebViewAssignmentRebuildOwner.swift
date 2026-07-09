//
//  WebViewAssignmentRebuildOwner.swift
//  Sumi
//
//  Owns normal-tab WebView assignment and live rebuild sequencing.
//

import Foundation
import WebKit
import SumiWebRuntime

@MainActor
final class WebViewAssignmentRebuildOwner {
    typealias RegisterTrackedWebView = (WKWebView, UUID, UUID) -> Void
    typealias UnregisterTrackedWebViewSlot = (TrackedWebViewOwner, WKWebView?) -> WKWebView?
    typealias ContainerRemoval = (WKWebView) -> Void
    typealias ProtectedWebViewCheck = (WKWebView) -> Bool
    typealias ProtectedRebuildDeferral = (WKWebView, UUID, UUID?) -> Void
    typealias PrimaryCandidateResolver = (UUID) -> (owner: TrackedWebViewOwner, webView: WKWebView)?
    typealias LiveWindowSelectionProvider = () -> LiveWindowSelection
    typealias CompositorRefresh = (UUID) -> Void
    typealias TabActivationNotifier = (any WebRuntimeTabHandle, UUID) -> Void
    /// App-owned initial-document handoff for factory primary create / rebuild.
    typealias SchedulePrimaryInitialDocumentLoad = (
        _ webView: WKWebView,
        _ tab: any WebRuntimeTabHandle,
        _ ownership: any WebRuntimeTabOwnershipMutating,
        _ mainFrameLoading: any WebRuntimeTabMainFrameLoading,
        _ reason: String
    ) -> Void
    /// App-owned clone initial-document handoff (`NormalTabInitialDocumentRuntimeHandoff`).
    typealias ScheduleCloneInitialDocumentLoad = (
        _ webView: WKWebView,
        _ tab: any WebRuntimeTabHandle,
        _ mainFrameLoading: any WebRuntimeTabMainFrameLoading,
        _ targetURL: URL
    ) -> Void

    enum LiveWindowSelection {
        case allTrackedWindows
        case liveWindows(Set<UUID>)
    }

    struct Runtime {
        let webViewRegistry: WindowWebViewRegistry
        let tabWebViewSessionStore: TabWebViewSessionStore?
        let initialDocumentWarmupRuntime: InitialDocumentWarmupRuntime?
        let registerTrackedWebView: RegisterTrackedWebView
        let unregisterTrackedWebViewSlot: UnregisterTrackedWebViewSlot
        let removeFromContainers: ContainerRemoval
        let isWebViewProtectedFromCompositorMutation: ProtectedWebViewCheck
        let deferProtectedRebuild: ProtectedRebuildDeferral
        let primaryCandidate: PrimaryCandidateResolver
        let liveWindowSelection: LiveWindowSelectionProvider
        let refreshCompositor: CompositorRefresh
        let notifyTabActivatedIfCurrent: TabActivationNotifier
        /// Y3/Y4: live protocol witnesses. Assembler passes the operation `Tab`
        /// (conforms). Tests may inject alternate witnesses; when nil, falls
        /// back to casting the concrete `Tab` entry argument.
        let tabMaterializing: (any WebRuntimeTabMaterializing)?
        let tabOwnership: (any WebRuntimeTabOwnershipMutating)?
        let tabTeardown: (any WebRuntimeTabTeardownLifecycle)?
        let tabSiteReloadPolicy: (any WebRuntimeTabSiteReloadPolicyNotifying)?
        let tabMainFrameLoading: (any WebRuntimeTabMainFrameLoading)?
        let tabAudioMute: (any WebRuntimeTabAudioMuteSnapshotting)?
        let schedulePrimaryInitialDocumentLoad: SchedulePrimaryInitialDocumentLoad
        let scheduleCloneInitialDocumentLoad: ScheduleCloneInitialDocumentLoad

        init(
            webViewRegistry: WindowWebViewRegistry,
            tabWebViewSessionStore: TabWebViewSessionStore?,
            initialDocumentWarmupRuntime: InitialDocumentWarmupRuntime?,
            registerTrackedWebView: @escaping RegisterTrackedWebView,
            unregisterTrackedWebViewSlot: @escaping UnregisterTrackedWebViewSlot,
            removeFromContainers: @escaping ContainerRemoval,
            isWebViewProtectedFromCompositorMutation: @escaping ProtectedWebViewCheck,
            deferProtectedRebuild: @escaping ProtectedRebuildDeferral,
            primaryCandidate: @escaping PrimaryCandidateResolver,
            liveWindowSelection: @escaping LiveWindowSelectionProvider,
            refreshCompositor: @escaping CompositorRefresh,
            notifyTabActivatedIfCurrent: @escaping TabActivationNotifier,
            tabMaterializing: (any WebRuntimeTabMaterializing)? = nil,
            tabOwnership: (any WebRuntimeTabOwnershipMutating)? = nil,
            tabTeardown: (any WebRuntimeTabTeardownLifecycle)? = nil,
            tabSiteReloadPolicy: (any WebRuntimeTabSiteReloadPolicyNotifying)? = nil,
            tabMainFrameLoading: (any WebRuntimeTabMainFrameLoading)? = nil,
            tabAudioMute: (any WebRuntimeTabAudioMuteSnapshotting)? = nil,
            schedulePrimaryInitialDocumentLoad: @escaping SchedulePrimaryInitialDocumentLoad = { _, _, _, _, _ in },
            scheduleCloneInitialDocumentLoad: @escaping ScheduleCloneInitialDocumentLoad = { _, _, _, _ in }
        ) {
            self.webViewRegistry = webViewRegistry
            self.tabWebViewSessionStore = tabWebViewSessionStore
            self.initialDocumentWarmupRuntime = initialDocumentWarmupRuntime
            self.registerTrackedWebView = registerTrackedWebView
            self.unregisterTrackedWebViewSlot = unregisterTrackedWebViewSlot
            self.removeFromContainers = removeFromContainers
            self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
            self.deferProtectedRebuild = deferProtectedRebuild
            self.primaryCandidate = primaryCandidate
            self.liveWindowSelection = liveWindowSelection
            self.refreshCompositor = refreshCompositor
            self.notifyTabActivatedIfCurrent = notifyTabActivatedIfCurrent
            self.tabMaterializing = tabMaterializing
            self.tabOwnership = tabOwnership
            self.tabTeardown = tabTeardown
            self.tabSiteReloadPolicy = tabSiteReloadPolicy
            self.tabMainFrameLoading = tabMainFrameLoading
            self.tabAudioMute = tabAudioMute
            self.schedulePrimaryInitialDocumentLoad = schedulePrimaryInitialDocumentLoad
            self.scheduleCloneInitialDocumentLoad = scheduleCloneInitialDocumentLoad
        }
    }

    private let creationPlanningOwner = WebViewCreationPlanningOwner()

    private func resolvedMaterializing(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabMaterializing {
        runtime.tabMaterializing ?? tab
    }

    private func resolvedOwnership(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabOwnershipMutating {
        runtime.tabOwnership ?? tab
    }

    private func resolvedTeardown(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabTeardownLifecycle {
        runtime.tabTeardown ?? tab
    }

    private func resolvedSiteReloadPolicy(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabSiteReloadPolicyNotifying {
        runtime.tabSiteReloadPolicy ?? tab
    }

    private func resolvedMainFrameLoading(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabMainFrameLoading {
        runtime.tabMainFrameLoading ?? tab
    }

    private func resolvedAudioMute(
        for tab: Tab,
        runtime: Runtime
    ) -> any WebRuntimeTabAudioMuteSnapshotting {
        runtime.tabAudioMute ?? tab
    }

    private func resolvedHandle(for tab: Tab) -> any WebRuntimeTabHandle {
        tab
    }

    func getOrCreateWebView(
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        let handle = resolvedHandle(for: tab)
        switch creationPlanningOwner.creationPlan(
            for: handle,
            in: windowId,
            initialDocumentWarmupRuntime: runtime.initialDocumentWarmupRuntime,
            existingWebView: runtime.webViewRegistry.webView(for: handle.id, in: windowId),
            windowWebViews: runtime.webViewRegistry.windowWebViews(for: handle.id),
            sessionStore: runtime.tabWebViewSessionStore
        ) {
        case .useExisting(let existing):
            return existing
        case .adoptExistingPrimary(let adoptedWebView):
            adoptExistingPrimaryWebView(adoptedWebView, for: tab, in: windowId, runtime: runtime)
            return adoptedWebView
        case .deferForInitialDocumentWarmup(let deferral):
            creationPlanningOwner.startInitialDocumentWarmupIfNeeded(
                deferral,
                runtime: runtime.initialDocumentWarmupRuntime
            )
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
        runtime: Runtime
    ) {
        let handle = resolvedHandle(for: tab)
        let ownership = resolvedOwnership(for: tab, runtime: runtime)
        guard let replacement = runtime.primaryCandidate(handle.id) else {
            ownership.clearCurrentWebViewOwnership()
            runtime.tabWebViewSessionStore?.clearPrimaryAssignment(for: handle.id)
            return
        }

        let sessionPrimaryWindowId = runtime.tabWebViewSessionStore?.primaryWindowId(for: handle.id)
            ?? handle.localSession.primaryWindowId
        if !ownership.currentWebViewIsIdentical(to: replacement.webView)
            || sessionPrimaryWindowId != replacement.owner.windowID {
            ownership.assignWebViewToWindow(replacement.webView, windowId: replacement.owner.windowID)
            runtime.tabWebViewSessionStore?.notePrimaryAssignment(
                windowId: replacement.owner.windowID,
                for: handle.id,
                webView: replacement.webView
            )
        }
    }

    @available(macOS 15.5, *)
    @discardableResult
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID? = nil,
        load url: URL? = nil,
        runtime: Runtime
    ) -> Bool {
        let handle = resolvedHandle(for: tab)
        let trackedWindowIds = Set(runtime.webViewRegistry.windowIDs(for: handle.id))
        var targetWindowIds = trackedWindowIds

        if case .liveWindows(let liveWindowIds) = runtime.liveWindowSelection() {
            targetWindowIds.formIntersection(liveWindowIds)
        }

        guard targetWindowIds.isEmpty == false else { return false }

        let sessionStore = runtime.tabWebViewSessionStore
        let localSession = handle.localSession
        sessionStore?.promoteLocalSessionIfNeeded(tabId: handle.id, localSession: localSession)
        let sessionUntrackedURL = sessionStore?.untrackedWebView(for: handle.id)?.url
        let sessionParkedURL = sessionStore?.parkedWebView(for: handle.id)?.url
        let sessionPrimaryURL = sessionStore?.session(for: handle.id).primaryWebView?.url
        let targetURL = url
            ?? sessionPrimaryURL
            ?? sessionUntrackedURL
            ?? sessionParkedURL
            ?? handle.url
        let preferredPrimaryWindowIdCandidate: UUID?
        if let preferredPrimaryWindowId,
           targetWindowIds.contains(preferredPrimaryWindowId) {
            preferredPrimaryWindowIdCandidate = preferredPrimaryWindowId
        } else {
            preferredPrimaryWindowIdCandidate = nil
        }
        let registryPrimaryWindowIdCandidate: UUID?
        if let registryPrimaryWindowId = runtime.primaryCandidate(handle.id)?.owner.windowID,
           targetWindowIds.contains(registryPrimaryWindowId) {
            registryPrimaryWindowIdCandidate = registryPrimaryWindowId
        } else {
            registryPrimaryWindowIdCandidate = nil
        }
        let primaryWindowId = preferredPrimaryWindowIdCandidate
            ?? registryPrimaryWindowIdCandidate
            ?? targetWindowIds.sorted { $0.uuidString < $1.uuidString }.first

        guard let primaryWindowId else { return false }

        let protectedCandidateWebViews = sessionStore?.protectedCandidateWebViews(
            for: handle.id,
            localSession: localSession
        ) ?? Array(runtime.webViewRegistry.windowWebViews(for: handle.id).values)
        if protectedCandidateWebViews.contains(where: runtime.isWebViewProtectedFromCompositorMutation) {
            let deferredWebViews = protectedCandidateWebViews.filter(runtime.isWebViewProtectedFromCompositorMutation)
            for protectedWebView in deferredWebViews {
                runtime.deferProtectedRebuild(
                    protectedWebView,
                    handle.id,
                    preferredPrimaryWindowId
                )
            }
            return false
        }

        let oldEntries = runtime.webViewRegistry.windowWebViews(for: handle.id)
        let sessionKnownWebViews = sessionStore?.allKnownWebViews(
            for: handle.id,
            localSession: localSession
        ) ?? []
        var cleanedIdentifiers: Set<ObjectIdentifier> = []
        let teardown = resolvedTeardown(for: tab, runtime: runtime)

        func cleanup(_ webView: WKWebView?) {
            guard let webView else { return }
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            teardown.cleanupCloneWebView(webView)
        }

        for (windowId, webView) in oldEntries {
            runtime.removeFromContainers(webView)
            _ = runtime.unregisterTrackedWebViewSlot(
                TrackedWebViewOwner(tabID: handle.id, windowID: windowId),
                webView
            )
            cleanup(webView)
        }
        for webView in sessionKnownWebViews {
            cleanup(webView)
        }

        teardown.cancelPendingMainFrameNavigation()
        resolvedOwnership(for: tab, runtime: runtime).clearAllWebViewOwnership()
        sessionStore?.clearAll(for: handle.id)
        handle.url = targetURL

        guard let recreatedPrimary = resolvedMaterializing(for: tab, runtime: runtime).makeNormalTabWebView(
            reason: "WebViewCoordinator.rebuildLiveWebViews"
        ) else {
            assertionFailure("Unable to rebuild normal tab WebView without a resolved profile")
            return false
        }
        resolvedOwnership(for: tab, runtime: runtime).assignWebViewToWindow(
            recreatedPrimary,
            windowId: primaryWindowId
        )
        sessionStore?.notePrimaryAssignment(
            windowId: primaryWindowId,
            for: handle.id,
            webView: recreatedPrimary
        )
        runtime.registerTrackedWebView(recreatedPrimary, handle.id, primaryWindowId)
        var recreatedWebViews = [recreatedPrimary]

        for windowId in targetWindowIds
            .filter({ $0 != primaryWindowId })
            .sorted(by: { $0.uuidString < $1.uuidString }) {
            if let clone = createCloneWebView(
                for: tab,
                in: windowId,
                primaryWindowId: primaryWindowId,
                runtime: runtime
            ) {
                recreatedWebViews.append(clone)
            }
        }

        let mainFrameLoading = resolvedMainFrameLoading(for: tab, runtime: runtime)
        if let url {
            for webView in recreatedWebViews {
                loadRecreatedWebView(
                    webView,
                    mainFrameLoading: mainFrameLoading,
                    targetURL: url
                )
            }
        } else {
            // Factory create no longer runs Tab ensure handoff; restore initial load.
            runtime.schedulePrimaryInitialDocumentLoad(
                recreatedPrimary,
                handle,
                resolvedOwnership(for: tab, runtime: runtime),
                mainFrameLoading,
                "WebViewCoordinator.rebuildLiveWebViews"
            )
        }

        let siteReloadPolicy = resolvedSiteReloadPolicy(for: tab, runtime: runtime)
        siteReloadPolicy.updateSafariContentBlockerReloadRequirementForCurrentSite()
        siteReloadPolicy.updateProtectionReloadRequirementForCurrentSite()
        siteReloadPolicy.updateAutoplayReloadRequirementForCurrentSite()

        for windowId in targetWindowIds {
            runtime.refreshCompositor(windowId)
        }
        return true
    }

    private func loadRecreatedWebView(
        _ webView: WKWebView,
        mainFrameLoading: any WebRuntimeTabMainFrameLoading,
        targetURL: URL
    ) {
        mainFrameLoading.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: true
        ) { resolvedWebView in
            if targetURL.isFileURL {
                resolvedWebView.loadFileURL(
                    targetURL,
                    allowingReadAccessTo: targetURL.deletingLastPathComponent()
                )
            } else {
                resolvedWebView.load(
                    TabNavigationCommandOwner.navigationCommandURLRequest(for: targetURL)
                )
            }
        }
    }

    private func createPrimaryWebView(
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        let handle = resolvedHandle(for: tab)
        guard let webView = resolvedMaterializing(for: tab, runtime: runtime).makeNormalTabWebView(
            reason: "WebViewCoordinator.createPrimaryWebView"
        ) else {
            assertionFailure("Unable to create normal tab WebView without a resolved profile")
            return nil
        }
        resolvedOwnership(for: tab, runtime: runtime).assignWebViewToWindow(webView, windowId: windowId)
        runtime.tabWebViewSessionStore?.notePrimaryAssignment(
            windowId: windowId,
            for: handle.id,
            webView: webView
        )
        runtime.registerTrackedWebView(webView, handle.id, windowId)
        // Previously `ensureWebView` → setup handoff loaded http(s). Factory-only
        // create must schedule that load explicitly or pages stay blank.
        runtime.schedulePrimaryInitialDocumentLoad(
            webView,
            handle,
            resolvedOwnership(for: tab, runtime: runtime),
            resolvedMainFrameLoading(for: tab, runtime: runtime),
            "WebViewCoordinator.createPrimaryWebView"
        )
        return webView
    }

    private func createCloneWebView(
        for tab: Tab,
        in windowId: UUID,
        primaryWindowId: UUID,
        runtime: Runtime
    ) -> WKWebView? {
        let handle = resolvedHandle(for: tab)
        guard runtime.webViewRegistry.webView(for: handle.id, in: primaryWindowId) != nil else {
            assertionFailure("Cannot create a clone WebView before the primary WebView is tracked")
            return nil
        }
        guard let newWebView = resolvedMaterializing(for: tab, runtime: runtime).makeNormalTabWebView(
            reason: "WebViewCoordinator.createCloneWebView"
        ) else {
            assertionFailure("Unable to create normal tab clone WebView without a resolved profile")
            return nil
        }

        runtime.registerTrackedWebView(newWebView, handle.id, windowId)
        if let url = URL(string: handle.url.absoluteString) {
            runtime.scheduleCloneInitialDocumentLoad(
                newWebView,
                handle,
                resolvedMainFrameLoading(for: tab, runtime: runtime),
                url
            )
        }
        newWebView.sumiSetAudioMuted(resolvedAudioMute(for: tab, runtime: runtime).isAudioMuted)
        runtime.notifyTabActivatedIfCurrent(handle, windowId)
        return newWebView
    }

    private func adoptExistingPrimaryWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowId: UUID,
        runtime: Runtime
    ) {
        let handle = resolvedHandle(for: tab)
        runtime.registerTrackedWebView(webView, handle.id, windowId)
        resolvedOwnership(for: tab, runtime: runtime).assignWebViewToWindow(webView, windowId: windowId)
        runtime.tabWebViewSessionStore?.notePrimaryAssignment(
            windowId: windowId,
            for: handle.id,
            webView: webView
        )
    }
}
