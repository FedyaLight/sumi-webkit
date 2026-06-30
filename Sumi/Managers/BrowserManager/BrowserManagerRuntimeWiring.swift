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
        browserManager.splitManager.windowRegistry = browserManager.windowRegistry
        browserManager.tabManager.attachRuntimeContext(.live(browserManager: browserManager))
        browserManager.liveFolderManager.attach(runtime: liveFolderRuntime(for: browserManager))
        browserManager.downloadManager.retryRuntime = downloadRetryRuntime(for: browserManager)
        browserManager.extensionsModule.attach(browserManager: browserManager)
        browserManager.userscriptsModule.attach(browserManager: browserManager)
        browserManager.boostsModule.attach(runtime: boostRuntime(for: browserManager))
        let structuralChangeCancellable = bindTabManagerStructuralUpdates(for: browserManager)
        browserManager.auxiliaryWindowManager.attach(browserManager: browserManager)
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
            makePreviewTab: { [weak browserManager] url, sourceTab in
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
        browserManager: BrowserManager
    ) -> Tab {
        let sourceProfile = sourceTab?.resolveProfile()
        let targetSpace = sourceTab?.spaceId.flatMap { spaceId in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        } ?? browserManager.tabManager.currentSpace

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
        ?? browserManager.tabManager.currentSpace
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
