import Combine
import Foundation
import WebKit

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        browserManager.compositorManager.attach(runtime: .live(browserManager: browserManager))
        browserManager.tabSuspensionService.attach(runtime: tabSuspensionRuntime(for: browserManager))
        browserManager.backgroundMediaOptimizationService.attach(
            runtime: backgroundMediaOptimizationRuntime(for: browserManager)
        )
        browserManager.splitManager.attach(runtime: .live(browserManager: browserManager))
        browserManager.tabManager.attachRuntimeContext(.live(browserManager: browserManager))
        browserManager.liveFolderManager.attach(runtime: liveFolderRuntime(for: browserManager))
        browserManager.downloadManager.retryRuntime = downloadRetryRuntime(for: browserManager)
        browserManager.extensionsModule.attach(runtime: .live(browserManager: browserManager))
        browserManager.userscriptsModule.attach(runtime: .live(browserManager: browserManager))
        browserManager.boostsModule.attach(runtime: boostRuntime(for: browserManager))
        let structuralChangeCancellable = bindTabManagerStructuralUpdates(for: browserManager)
        browserManager.auxiliaryWindowManager.attach(runtime: auxiliaryWindowRuntime(for: browserManager))
        browserManager.glanceManager.attach(runtime: glanceRuntime(for: browserManager))
        browserManager.authenticationManager.attach(runtime: authenticationRuntime(for: browserManager))
        return structuralChangeCancellable
    }

    static func tabSelectionRuntimeNotifications(
        for browserManager: BrowserManager
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        BrowserTabSelectionOwner.RuntimeNotifications(
            tabActivated: { [weak browserManager] newTab, previousTab in
                guard let browserManager else { return }
                notifyExtensionTabActivated(
                    newTab,
                    previous: previousTab,
                    for: browserManager
                )
            },
            tabSelectionChanged: { [weak browserManager] reason in
                guard let browserManager else { return }
                scheduleTabRuntimeReconcile(for: browserManager, reason: reason)
            }
        )
    }

    static func nativeNowPlayingRuntimeContext(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingRuntimeContext {
        SumiNativeNowPlayingRuntimeContext.live(
            runtime: nativeNowPlayingBrowserRuntime(for: browserManager)
        )
    }

    private static func authenticationRuntime(
        for browserManager: BrowserManager
    ) -> AuthenticationManagerRuntime {
        AuthenticationManagerRuntime(
            presentBasicAuthSheet: { [weak browserManager] session, tab in
                guard let browserManager else { return false }
                return browserManager.presentBasicAuthSheet(
                    session,
                    in: browserManager.windowState(containing: tab)
                )
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.dismissNativeModalPresentation()
            }
        )
    }

    private static func liveFolderRuntime(
        for browserManager: BrowserManager
    ) -> SumiLiveFolderRuntime {
        SumiLiveFolderRuntime(
            spaceContext: { [weak browserManager] spaceId in
                guard let space = browserManager?.tabManager.spaces.first(where: { $0.id == spaceId }) else {
                    return nil
                }
                return SumiLiveFolderRuntime.SpaceContext(profileId: space.profileId)
            },
            createFolder: { [weak browserManager] spaceId, name in
                browserManager?.tabManager.createFolder(for: spaceId, name: name).id
            },
            updateFolderIcon: { [weak browserManager] folderId, icon in
                browserManager?.tabManager.updateFolderIcon(folderId, icon: icon)
            },
            renameFolder: { [weak browserManager] folderId, name in
                browserManager?.tabManager.renameFolder(folderId, newName: name)
            },
            openNewTab: { [weak browserManager] urlString, windowState, preferredSpaceId in
                browserManager?.openNewTab(
                    url: urlString,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            profile: { [weak browserManager] profileId, spaceId in
                guard let browserManager else { return nil }
                if let profileId,
                   let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
                    return profile
                }
                if let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }),
                   let profileId = space.profileId {
                    return browserManager.profileManager.profiles.first(where: { $0.id == profileId })
                }
                return browserManager.currentProfile
            },
            folderIds: { [weak browserManager] in
                guard let browserManager else { return nil }
                return Set(
                    browserManager.tabManager.foldersBySpace.values.flatMap { folders in
                        folders.map(\.id)
                    }
                )
            }
        )
    }

    private static func auxiliaryWindowRuntime(
        for browserManager: BrowserManager
    ) -> AuxiliaryWindowRuntime {
        AuxiliaryWindowRuntime(
            loadedEnabledExtensionManager: { [weak browserManager] in
                browserManager?.extensionsModule.managerIfLoadedAndEnabled()
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            currentSpace: { [weak browserManager] in
                browserManager?.tabManager.currentSpace
            },
            windowContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            createMiniWindowTab: { [weak browserManager] openerTab, profileId, urlString, contextOverride in
                browserManager?.tabManager.createAuxiliaryMiniWindowTab(
                    openerTab: openerTab,
                    profileId: profileId,
                    urlString: urlString,
                    webExtensionContextOverride: contextOverride
                )
            },
            removeMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.removeAuxiliaryMiniWindowTab(tab)
            },
            notifyTabClosedIfLoaded: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
            },
            registerExtensionCreatedTabIfLoaded: { [weak browserManager] tab, reason in
                browserManager?.extensionsModule.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    tab,
                    reason: reason
                )
            },
            popupPermissionBridge: { [weak browserManager] in
                browserManager?.popupPermissionBridge
            },
            filePickerPermissionBridge: { [weak browserManager] in
                browserManager?.filePickerPermissionBridge
            }
        )
    }

    static func notifyExtensionWindowOpened(
        _ windowState: BrowserWindowState,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyWindowOpenedIfLoaded(windowState)
    }

    static func notifyExtensionWindowFocused(
        _ windowState: BrowserWindowState,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyWindowFocusedIfLoaded(windowState)
    }

    static func notifyExtensionTabClosed(
        _ tab: Tab,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyTabClosedIfLoaded(tab)
    }

    private static func bindTabManagerStructuralUpdates(
        for browserManager: BrowserManager
    ) -> AnyCancellable {
        browserManager.tabManager.structuralChanges
            .receive(on: RunLoop.main)
            .sink { [weak browserManager] _ in
                guard let browserManager else { return }
                handleTabManagerStructuralChange(for: browserManager)
            }
    }

    private static func handleTabManagerStructuralChange(for browserManager: BrowserManager) {
        browserManager.tabStructuralRevision &+= 1
        scheduleTabRuntimeReconcile(for: browserManager, reason: "tab-structure-changed")
    }

    private static func notifyExtensionTabActivated(
        _ newTab: Tab,
        previous: Tab?,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyTabActivatedIfLoaded(
            newTab: newTab,
            previous: previous
        )
    }

    private static func scheduleTabRuntimeReconcile(
        for browserManager: BrowserManager,
        reason: String
    ) {
        browserManager.tabSuspensionService.scheduleProactiveTimerReconcile(reason: reason)
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
    }

    private static func backgroundMediaOptimizationRuntime(
        for browserManager: BrowserManager
    ) -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            energySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?.energySaverActivation.isActive ?? false
            },
            allKnownTabs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allRuntimeTabs(for: browserManager)
            },
            visibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return backgroundMediaVisibleTabIDsByWindow(for: browserManager)
            }
        )
    }

    private static func tabSuspensionRuntime(
        for browserManager: BrowserManager
    ) -> TabSuspensionRuntime {
        TabSuspensionRuntime(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            memoryMode: { [weak browserManager] in
                browserManager?.sumiSettings?.memoryMode ?? .balanced
            },
            customDeactivationDelay: { [weak browserManager] in
                browserManager?.sumiSettings?.memorySaverCustomDeactivationDelay
                    ?? SumiMemorySaverCustomDelay.defaultDelay
            },
            energySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?
                    .energySaverApplies(.deactivateInactiveTabsSooner) ?? false
            },
            allKnownTabs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allRuntimeTabs(for: browserManager)
            },
            selectedTabIDs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return tabSuspensionSelectedTabIDs(for: browserManager)
            },
            visibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return tabSuspensionVisibleTabIDsByWindow(for: browserManager)
            },
            refreshLazyRestoreQueue: { [weak browserManager] context in
                guard let browserManager else { return }
                refreshTabSuspensionLazyRestoreQueue(context, for: browserManager)
            }
        )
    }

    private static func nativeNowPlayingBrowserRuntime(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingBrowserRuntime {
        SumiNativeNowPlayingBrowserRuntime(
            windowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.windows.values.map { $0 } ?? []
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            mediaCandidateTabs: { [weak browserManager] windowState in
                browserManager?.windowScopedMediaCandidateTabs(in: windowState) ?? []
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            resolvedNowPlayingWebView: { [weak browserManager] tab, windowState in
                guard let browserManager else { return nil }
                return browserManager.windowOwnedWebView(for: tab, in: windowState.id)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }

    private static func downloadRetryRuntime(
        for browserManager: BrowserManager
    ) -> DownloadManager.RetryRuntime {
        DownloadManager.RetryRuntime(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            }
        )
    }

    private static func boostRuntime(
        for browserManager: BrowserManager
    ) -> SumiBoostsModule.Runtime {
        SumiBoostsModule.Runtime(
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            },
            matchingLivePages: { [weak browserManager] profileId, host in
                guard let browserManager else { return [] }
                return matchingBoostLivePages(
                    browserManager: browserManager,
                    profileId: profileId,
                    host: host
                )
            },
            applyBoostAwareZoom: { [weak browserManager] tab, webView in
                browserManager?.applyBoostAwareZoom(for: tab, webView: webView)
            },
            openWebInspector: { [weak browserManager] tab, windowState in
                browserManager?.openWebInspector(for: tab, in: windowState)
            }
        )
    }

    private static func glanceRuntime(for browserManager: BrowserManager) -> GlanceManager.Runtime {
        GlanceManager.Runtime(
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            hasLoadedInitialTabData: { [weak browserManager] in
                browserManager?.tabManager.hasLoadedInitialData ?? false
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            shortcutPin: { [weak browserManager] pinId in
                browserManager?.tabManager.shortcutPin(by: pinId)
            },
            shortcutLiveTab: { [weak browserManager] pinId, windowId in
                browserManager?.tabManager.shortcutLiveTab(for: pinId, in: windowId)
            },
            activateShortcutPin: { [weak browserManager] pin, windowId, currentSpaceId in
                guard let browserManager else {
                    return Tab(url: pin.launchURL, name: pin.title)
                }
                return browserManager.tabManager.activateShortcutPin(
                    pin,
                    in: windowId,
                    currentSpaceId: currentSpaceId
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            restoreSourceSelection: { [weak browserManager] tab, windowState in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: true,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false,
                    loadPolicy: .deferred
                )
            },
            visibleSplitTabCount: { [weak browserManager] windowId in
                browserManager?.splitManager.visibleTabIds(for: windowId).count ?? 0
            },
            dismissFloatingBarIfVisible: { [weak browserManager] windowId in
                browserManager?.dismissFloatingBarIfVisible(in: windowId) ?? false
            },
            isFindBarVisible: { [weak browserManager] in
                browserManager?.findManager.isFindBarVisible ?? false
            },
            findCurrentTabId: { [weak browserManager] in
                browserManager?.findManager.currentTab?.id
            },
            hideFindBar: { [weak browserManager] in
                browserManager?.findManager.hideFindBar()
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.updateFindManagerCurrentTab()
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            makePreviewTab: { [weak browserManager] url, sourceTab, windowState in
                guard let browserManager else {
                    return Tab(
                        url: url,
                        name: url.host ?? "Glance",
                        favicon: "globe",
                        index: 0
                    )
                }
                return makeGlancePreviewTab(
                    for: url,
                    sourceTab: sourceTab,
                    windowState: windowState,
                    browserManager: browserManager
                )
            },
            adoptPreviewTab: { [weak browserManager] previewTab, sourceTab, windowState in
                guard let browserManager else { return previewTab }
                return browserManager.tabManager.adoptGlanceTab(
                    previewTab,
                    sourceTab: sourceTab,
                    in: glanceTargetSpace(
                        sourceTab: sourceTab,
                        windowState: windowState,
                        browserManager: browserManager
                    )
                )
            },
            selectPromotedTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            selectPromotedTabInActiveWindow: { [weak browserManager] tab in
                browserManager?.selectTab(tab)
            },
            createSplitPlaceholder: { [weak browserManager] windowState in
                browserManager?.splitManager.createEmptySplit(
                    side: .right,
                    in: windowState,
                    floatingBarPresentationReason: .splitTabPicker
                )
            },
            registerPromotedHost: { [weak browserManager] host, tabId, windowId, attachmentCompletion in
                guard let webViewCoordinator = browserManager?.webViewCoordinator else {
                    return false
                }
                webViewCoordinator.registerPromotedHost(
                    host,
                    for: tabId,
                    in: windowId,
                    attachmentCompletion: attachmentCompletion
                )
                return true
            }
        )
    }

    private static func makeGlancePreviewTab(
        for url: URL,
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        browserManager: BrowserManager
    ) -> Tab {
        let sourceProfile = sourceTab?.resolveProfile()
        let targetSpace = glanceTargetSpace(
            sourceTab: sourceTab,
            windowState: windowState,
            browserManager: browserManager
        )

        let tab = Tab(
            url: url,
            name: url.host ?? "Glance",
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0
        )
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
        tab.profileId = sourceProfile?.id ?? targetSpace?.profileId ?? browserManager.currentProfile?.id
        return tab
    }

    private static func glanceTargetSpace(
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        browserManager: BrowserManager
    ) -> Space? {
        windowState?.currentSpaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        }
        ?? sourceTab?.spaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        }
    }

    private static func matchingBoostLivePages(
        browserManager: BrowserManager,
        profileId: UUID,
        host: String
    ) -> [SumiBoostsModule.LivePage] {
        var visited = Set<ObjectIdentifier>()
        var pages: [SumiBoostsModule.LivePage] = []

        func tabMatches(_ tab: Tab) -> Bool {
            (tab.resolveProfile()?.id ?? tab.profileId) == profileId
                && SumiBoostURLPolicy.normalizedBoostableHost(for: tab.url) == host
        }

        func visit(_ tab: Tab, _ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard visited.insert(identifier).inserted else { return }
            pages.append(SumiBoostsModule.LivePage(tab: tab, webView: webView))
        }

        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            for tab in browserManager.tabsForDisplay(in: windowState) where tabMatches(tab) {
                if let webView = browserManager.windowOwnedWebView(for: tab, in: windowState.id) {
                    visit(tab, webView)
                }
            }
        }

        for tab in browserManager.tabManager.allTabs() where tabMatches(tab) {
            for webView in browserManager.webViewCoordinator?.getAllWebViews(for: tab.id) ?? [] {
                visit(tab, webView)
            }
        }

        return pages
    }

    private static func backgroundMediaVisibleTabIDsByWindow(
        for browserManager: BrowserManager
    ) -> [UUID: Set<UUID>] {
        guard let windowRegistry = browserManager.windowRegistry else { return [:] }

        var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
        for windowState in windowRegistry.windows.values where windowState.windowVisibilityState.isEffectivelyVisible {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visibleTabIDsByWindow[windowState.id] = Set(tabIDs)
        }
        return visibleTabIDsByWindow
    }

    private static func tabSuspensionSelectedTabIDs(
        for browserManager: BrowserManager
    ) -> Set<UUID> {
        var selectedIDs = Set<UUID>()
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            if let current = browserManager.currentTab(for: windowState) {
                selectedIDs.insert(current.id)
            }
        }
        if let current = browserManager.tabManager.currentTab {
            selectedIDs.insert(current.id)
        }
        return selectedIDs
    }

    private static func tabSuspensionVisibleTabIDsByWindow(
        for browserManager: BrowserManager
    ) -> [UUID: Set<UUID>] {
        var visible: [UUID: Set<UUID>] = [:]
        for windowState in browserManager.windowRegistry?.windows.values.map({ $0 }) ?? [] {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visible[windowState.id] = Set(tabIDs)
        }
        return visible
    }

    private static func refreshTabSuspensionLazyRestoreQueue(
        _ context: TabSuspensionEvaluationContext,
        for browserManager: BrowserManager
    ) {
        guard let windowRegistry = browserManager.windowRegistry else { return }

        let activeWindowId = windowRegistry.activeWindow?.id
        let anchors = windowRegistry.allWindows
            .sorted { lhs, rhs in
                let lhsPriority = lhs.id == activeWindowId ? 0 : 1
                let rhsPriority = rhs.id == activeWindowId ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { windowState in
                let currentTab = browserManager.currentTab(for: windowState)
                return browserManager.tabManager.opportunisticRestoreAnchor(
                    in: windowState,
                    currentTab: currentTab
                )
            }

        browserManager.tabManager.lazyRestoreCoordinator.refresh(
            anchors: anchors,
            selectedTabIDs: context.selectedTabIDs,
            visibleTabIDs: context.visibleTabIDs
        )
    }

    private static func allRuntimeTabs(
        for browserManager: BrowserManager
    ) -> [Tab] {
        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        browserManager.tabManager.allTabs().forEach(append)
        (browserManager.windowRegistry?.windows.values.map { $0 } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }
}

extension SplitViewRuntime {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let fallbackTabManager = browserManager.tabManager
        return Self(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager ?? fallbackTabManager
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState in
                browserManager?.schedulePersistWindowSession(for: windowState)
            },
            focusFloatingBar: { [weak browserManager] windowState, reason in
                browserManager?.focusFloatingBar(
                    in: windowState,
                    prefill: "",
                    navigateCurrentTab: true,
                    presentationReason: reason
                )
            }
        )
    }
}

extension TabManagerRuntimeContext {
    static func live(browserManager: BrowserManager) -> TabManagerRuntimeContext {
        TabManagerRuntimeContext(
            currentProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            defaultProfileId: { [weak browserManager] in
                browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            profileExists: { [weak browserManager] profileId in
                guard let browserManager else { return true }
                return browserManager.profileManager.profiles.contains { $0.id == profileId }
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            windows: { [weak browserManager] in
                browserManager?.windowRegistry?.windows.map { ($0.key, $0.value) } ?? []
            },
            windowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            updateTabVisibility: { [weak browserManager] in
                browserManager?.compositorManager.updateTabVisibility()
            },
            materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            loadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.loadTab(tab)
            },
            unloadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.unloadTab(tab)
            },
            requireRemoveAllWebViews: { [weak browserManager] tab, closeActiveFullscreenMedia in
                guard let browserManager else { return }
                browserManager.requireWebViewCoordinator().removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                )
            },
            windowIDsTrackingWebViews: { [weak browserManager] tabId in
                browserManager?.webViewCoordinator?.windowIDs(for: tabId) ?? []
            },
            rebuildLiveWebViews: { [weak browserManager] tab, preferredPrimaryWindowId, url in
                if #available(macOS 15.5, *) {
                    browserManager?.webViewCoordinator?.rebuildLiveWebViews(
                        for: tab,
                        preferredPrimaryWindowId: preferredPrimaryWindowId,
                        load: url
                    )
                }
            },
            handleTabClosure: { [weak browserManager] tabId in
                browserManager?.splitManager.handleTabClosure(tabId)
            },
            visibleSplitTabIds: { [weak browserManager] windowId in
                browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
            },
            isTabVisibleInSplit: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.isTabVisibleInSplit(tabId, in: windowId) == true
            },
            isTabActiveInSplit: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.isTabActiveInSplit(tabId, in: windowId) == true
            },
            updateActiveSplitSide: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
            },
            notifyTabClosedIfLoaded: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] newTab, previous in
                browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: newTab,
                    previous: previous
                )
            },
            captureClosedTab: { [weak browserManager] tab, sourceSpaceId in
                browserManager?.recentlyClosedManager.captureClosedTab(
                    tab,
                    sourceSpaceId: sourceSpaceId,
                    currentURL: tab.url,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                )
            },
            captureDeletedShortcutLauncher: { [weak browserManager] pin in
                browserManager?.recentlyClosedManager.captureDeletedShortcutLauncher(pin)
            },
            presentTabClosureToast: { [weak browserManager] tabCount in
                browserManager?.presentTabClosureToast(tabCount: tabCount)
            },
            validateWindowStates: { [weak browserManager] in
                browserManager?.validateWindowStates()
            },
            syncWorkspaceThemeAcrossWindows: { [weak browserManager] space, animate in
                browserManager?.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
            },
            closeAuxiliaryMiniWindow: { [weak browserManager] tab, reason in
                browserManager?.closeAuxiliaryMiniWindow(for: tab, reason: reason)
            },
            isLiveFolder: { [weak browserManager] folderId in
                browserManager?.liveFolderManager.isLiveFolder(folderId) == true
            },
            deleteLiveFolderState: { [weak browserManager] folderIds in
                browserManager?.liveFolderManager.deleteState(forFolderIds: folderIds)
            },
            prepareTab: { [weak browserManager] tab in
                guard let browserManager else { return }
                tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
            }
        )
    }
}

extension HoverSidebarRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        HoverSidebarRuntime(
            browserRuntimeAvailable: { [weak browserManager] in
                browserManager != nil
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}

extension SumiScriptsManagerRuntime {
    private struct UserscriptSourceContext {
        let tab: Tab
        let openerTab: Tab?
        let windowState: BrowserWindowState?
        let spaceId: UUID?

        var tabForOpeningPlacement: Tab {
            openerTab ?? tab
        }
    }

    static func live(browserManager: BrowserManager) -> Self {
        Self(
            injectorRuntime: { [weak browserManager] in
                guard let browserManager else { return .inactive }
                return .live(browserManager: browserManager)
            },
            openTab: { [weak browserManager] url, background, sourceWebView in
                guard let browserManager else { return }
                let sourceContext = userscriptSourceContext(
                    for: sourceWebView,
                    browserManager: browserManager
                )
                let fallbackWindow = sourceWebView == nil ? browserManager.windowRegistry?.activeWindow : nil
                let targetWindow = sourceContext?.windowState ?? fallbackWindow
                let preferredSpaceId = sourceContext?.spaceId ?? targetWindow?.currentSpaceId
                let openContext: BrowserTabOpenContext
                if background {
                    openContext = .background(
                        windowState: targetWindow,
                        sourceTab: sourceContext?.tabForOpeningPlacement,
                        preferredSpaceId: preferredSpaceId
                    )
                } else if let targetWindow {
                    openContext = .foreground(
                        windowState: targetWindow,
                        sourceTab: sourceContext?.tabForOpeningPlacement,
                        preferredSpaceId: preferredSpaceId
                    )
                } else {
                    guard let targetSpace = preferredSpaceId.flatMap({ spaceId in
                        browserManager.tabManager.spaces.first { $0.id == spaceId }
                    }) else { return }
                    _ = browserManager.tabManager.createNewTab(
                        url: url,
                        in: targetSpace,
                        activate: false
                    )
                    return
                }
                browserManager.openNewTab(url: url, context: openContext)
            },
            closeTab: { [weak browserManager] tabId, sourceWebView in
                guard let browserManager else { return }
                if let tabId, let uuid = UUID(uuidString: tabId) {
                    closeUserscriptTab(
                        uuid,
                        sourceWebView: sourceWebView,
                        browserManager: browserManager
                    )
                } else if let sourceContext = userscriptSourceContext(
                    for: sourceWebView,
                    browserManager: browserManager
                ) {
                    closeUserscriptTab(sourceContext.tab, sourceContext.windowState, browserManager)
                } else if sourceWebView == nil,
                          let activeWindow = browserManager.windowRegistry?.activeWindow,
                          let activeTab = browserManager.currentTab(for: activeWindow) {
                    browserManager.closeTab(activeTab, in: activeWindow)
                }
            }
        )
    }

    private static func userscriptSourceContext(
        for sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) -> UserscriptSourceContext? {
        guard let sourceWebView else { return nil }

        if let auxiliarySession = browserManager.auxiliaryWindowManager.session(for: sourceWebView) {
            let openerWindowState = auxiliarySession.openerWindow.flatMap {
                browserManager.windowRegistry?.windowState(containing: $0)
            }
            let sourceTab = auxiliarySession.openerTab ?? auxiliarySession.tab
            return UserscriptSourceContext(
                tab: auxiliarySession.tab,
                openerTab: auxiliarySession.openerTab,
                windowState: openerWindowState,
                spaceId: auxiliarySession.tab.spaceId ?? sourceTab.spaceId ?? openerWindowState?.currentSpaceId
            )
        }

        guard let owner = browserManager.trackedWebViewOwner(containing: sourceWebView),
              let tab = browserManager.tabManager.tab(for: owner.tabID)
        else {
            return nil
        }

        let windowState = browserManager.windowRegistry?.windows[owner.windowID]
        return UserscriptSourceContext(
            tab: tab,
            openerTab: nil,
            windowState: windowState,
            spaceId: tab.spaceId ?? windowState?.currentSpaceId
        )
    }

    private static func closeUserscriptTab(
        _ tabId: UUID,
        sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) {
        guard let tab = browserManager.tabManager.tab(for: tabId) else { return }
        let sourceWindow = userscriptSourceContext(
            for: sourceWebView,
            browserManager: browserManager
        )?.windowState
        let windowState = browserManager.windowState(containing: tab) ?? sourceWindow
        closeUserscriptTab(tab, windowState, browserManager)
    }

    private static func closeUserscriptTab(
        _ tab: Tab,
        _ windowState: BrowserWindowState?,
        _ browserManager: BrowserManager
    ) {
        if browserManager.tabManager.isAuxiliaryMiniWindowTab(tab) {
            browserManager.closeAuxiliaryMiniWindow(for: tab, reason: .extensionRequestedClose)
            return
        }

        if let windowState {
            browserManager.closeTab(tab, in: windowState)
        } else {
            browserManager.tabManager.removeTab(tab.id)
        }
    }
}

extension SumiExtensionsModuleRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            attachManager: { [weak browserManager] manager in
                guard let browserManager else { return }
                manager.attach(browserManager: browserManager)
            },
            liveTabs: { [weak browserManager] in
                browserManager?.tabManager.allTabs() ?? []
            },
            invalidateTabStructuralRevision: { [weak browserManager] in
                browserManager?.tabStructuralRevision &+= 1
            }
        )
    }
}

extension ExtensionManagerRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            ephemeralProfile: { [weak browserManager] profileId in
                browserManager?.windowRegistry?.windows.values
                    .compactMap(\.ephemeralProfile)
                    .first { $0.id == profileId }
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            activeWindowState: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            allTabs: { [weak browserManager] in
                browserManager?.tabManager.allTabs() ?? []
            },
            allWindowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            },
            trackedWebViews: { [weak browserManager] tabId in
                browserManager?.webViewCoordinator?.getAllWebViews(for: tabId) ?? []
            },
            rebuildLiveWebViews: { [weak browserManager] tab in
                browserManager?.webViewCoordinator?.rebuildLiveWebViews(for: tab)
            },
            browserRuntimeAvailable: { [weak browserManager] in
                browserManager != nil
            },
            extensionsModuleEnabled: { [weak browserManager] in
                browserManager?.extensionsModule.isEnabled
            }
        )
    }
}

extension UserScriptInjectorRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            },
            notificationPermissionBridge: { [weak browserManager] in
                browserManager?.notificationPermissionBridge
            },
            notificationTabContext: { [weak browserManager] webViewId, webView in
                browserManager?.tabManager.tab(for: webViewId)?
                    .webNotificationTabContext(for: webView)
            }
        )
    }
}
