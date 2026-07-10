//
//  BrowserWindowSessionBundle.swift
//  Sumi
//
//  Phase 5A / N2 capability bag: window session, tab context, visual mutation,
//  window-scoped navigation, restore, and shell commands.
//

import Foundation

/// Composes independent window-session persistence, scheduling, snapshot, and
/// restore capabilities with the browser's window owners.
@MainActor
final class BrowserWindowSessionBundle {
    let restoreService: WindowSessionRestoreService
    let commands: BrowserWindowSessionCommands
    let spaceStateOwner: BrowserWindowSpaceStateOwner
    let tabContextOwner: BrowserWindowTabContextOwner
    let visualMutationOwner: BrowserWindowVisualMutationOwner
    let scopedNavigationOwner: BrowserWindowScopedNavigationOwner
    let restoration: BrowserWindowSessionRestorationService
    let activation: BrowserWindowActivationService
    let persistence: WindowSessionPersistenceCoordinator
    let historySessionOwner: BrowserWindowHistorySessionOwner
    let recentlyClosedRestoreOwner: BrowserRecentlyClosedRestoreOwner
    let windowStateValidationOwner: BrowserWindowStateValidationOwner

    init(
        browserManager: BrowserManager,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    ) {
        let snapshotFactory = WindowSessionSnapshotFactory(
            splitManager: browserManager.splitManager,
            glanceManager: browserManager.glanceManager
        )
        let persistenceScheduler =
            browserManager.windowSessionPersistenceScheduler
        let persistenceService = WindowSessionPersistenceService(
            store: browserManager.windowSessionSnapshotStore,
            scheduler: persistenceScheduler,
            snapshotFactory: snapshotFactory
        )
        let restoreService = WindowSessionRestoreService(
            snapshotStore: browserManager.windowSessionSnapshotStore,
            persistence: persistenceService,
            tabManager: browserManager.tabManager,
            glanceManager: browserManager.glanceManager,
            selectionService: browserManager.shellSelectionService,
            selection: browserManager,
            floatingBarSanitizer: browserManager.urlBarBundle
                .floatingBarRoutingOwner,
            themeCommitter: browserManager.chromeBundle
                .workspaceThemeTransitionOwner,
            splitFocus: browserManager.sidebarCommandService
                .splitShortcutRouting
        )
        self.restoreService = restoreService
        self.commands = BrowserWindowSessionCommands(browserManager: browserManager)
        self.windowStateValidationOwner = BrowserWindowStateValidationOwner(
            browserManager: browserManager
        )
        let selectionService = browserManager.shellSelectionService
        self.spaceStateOwner = BrowserWindowSpaceStateOwner(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            selectionService: selectionService,
            sanitizeFloatingBarState: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.floatingBarRoutingOwner.sanitizeFloatingBarState(in: windowState)
            },
            syncShortcutSelectionState: { [weak browserManager] windowState in
                browserManager?.syncShortcutSelectionState(for: windowState)
            },
            updateWorkspaceTheme: { [weak browserManager] windowState, theme, animate in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner.updateWorkspaceTheme(
                    for: windowState,
                    to: theme,
                    animate: animate
                )
            },
            finishInteractiveSpaceTransition: { [weak browserManager] space, windowState, identity in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner.finishInteractiveSpaceTransition(
                    to: space,
                    in: windowState,
                    identity: identity
                )
            },
            applyTabSelection: { [weak browserManager] tab, windowState, updateSpaceFromTab, updateTheme, rememberSelection, persistSelection in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: updateSpaceFromTab,
                    updateTheme: updateTheme,
                    rememberSelection: rememberSelection,
                    persistSelection: persistSelection
                )
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.windowSessionBundle.visualMutationOwner.performImmediateVisualHandoffIfPossible(
                    in: windowState
                )
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            adoptProfileForSpaceChange: { [weak browserManager] windowState in
                browserManager?.adoptProfileIfNeeded(for: windowState, context: .spaceChange)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            completePendingSplitGroupFocusIfReady: { [weak browserManager] windowState, spaceId in
                browserManager?.sidebarCommandService.splitShortcutRouting.completePendingSplitGroupFocusIfReady(
                    in: windowState,
                    spaceId: spaceId
                )
            },
            updateProfileRuntimeStates: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.windowStateValidationOwner.updateProfileRuntimeStates(
                    activeWindowState: windowState
                )
            },
            validateWindowStates: { [weak browserManager] in
                browserManager?.windowSessionBundle.windowStateValidationOwner.validateWindowStates()
            }
        )
        self.tabContextOwner = BrowserWindowTabContextOwner(
            selectionService: { [weak browserManager] in
                browserManager?.shellSelectionService
            },
            tabStore: { [weak browserManager] in
                browserManager?.tabManager.runtimeStore
            },
            windows: { [weak browserManager] in
                guard let browserManager,
                      let windowRegistry = browserManager.windowRegistry
                else {
                    return []
                }
                return Array(windowRegistry.windows.values)
            },
            liveShortcutTabs: { [weak browserManager] windowId in
                browserManager?.tabManager.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            visibleSplitTabIds: { [weak browserManager] windowId in
                Set(browserManager?.splitManager.visibleTabIds(for: windowId) ?? [])
            }
        )
        self.visualMutationOwner = BrowserWindowVisualMutationOwner(
            hasActiveHistorySwipe: { [weak browserManager] windowId in
                browserManager?.webViewCoordinator?.protectionRuntime
                    .hasActiveHistorySwipe(in: windowId) == true
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowId in
                browserManager?.webViewCoordinator?.compositorRuntime
                    .performImmediateVisualHandoffIfPossible(in: windowId)
                    ?? false
            },
            prepareVisibleWebViews: { [weak browserManager] windowState in
                guard let browserManager else { return false }
                return browserManager.shellRuntime.requireWebViewCoordinator()
                    .visiblePreparationService.prepare(for: windowState)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                guard let browserManager else { return }
                browserManager.shellRuntime.requireWebViewCoordinator()
                    .visiblePreparationService.schedule(for: windowState)
            }
        )
        self.scopedNavigationOwner = BrowserWindowScopedNavigationOwner(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            materializeWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewOwnershipService?.webView(
                    for: tab,
                    in: windowId
                )
            },
            reloadTab: { [weak browserManager] tabId, windowId, intent, policy in
                browserManager?.webViewRoutingService.reloadTab(
                    tabId,
                    in: windowId,
                    intent: intent,
                    policy: policy
                ) ?? .failed
            },
            resolvedSearchEngineTemplate: { [weak browserManager] in
                browserManager?.sumiSettings?.resolvedSearchEngineTemplate
            }
        )
        self.recentlyClosedRestoreOwner = BrowserRecentlyClosedRestoreOwner(
            recentlyClosedManager: { [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            startupRestore: startupSessionRestoreOwner,
            lastSessionWindowsStore: { [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
            },
            currentRegularWindowSnapshots: { [weak browserManager] excludedWindowId in
                browserManager?.windowSessionBundle.historySessionOwner.currentRegularWindowSnapshots(excludingWindowID: excludedWindowId) ?? []
            },
            refreshLastSessionWindowsStore: { [weak browserManager] excludedWindowId in
                browserManager?.windowSessionBundle.historySessionOwner.refreshLastSessionWindowsStore(excludingWindowID: excludedWindowId)
            },
            reopenWindow: { [weak browserManager] snapshot in
                await browserManager?.historyBundle.historyMenuOwner.reopenWindow(from: snapshot)
            },
            mergeSnapshotForLastSessionRestore: { [weak browserManager] snapshot in
                browserManager?.tabManager.lastSessionMergeMaterializer
                    .merge(snapshot)
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            profileManager: { [weak browserManager, profileManager = browserManager.profileManager] in
                browserManager?.profileManager ?? profileManager
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSessionBundle.spaceStateOwner.space(for: spaceId)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
        let historySession = BrowserWindowHistorySessionOwner(
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            makeWindowSessionSnapshot: { windowState in
                return snapshotFactory.make(for: windowState)
            },
            windowDisplayTitle: { [weak browserManager] windowState in
                guard let browserManager else { return "" }
                if let currentTab = browserManager.windowSessionBundle.tabContextOwner.currentTab(for: windowState) {
                    return currentTab.name
                }
                if let currentSpace = browserManager.windowSessionBundle.spaceStateOwner.space(
                    for: windowState.currentSpaceId
                ) {
                    return currentSpace.name
                }
                return "Window"
            },
            recentlyClosedManager: {
                [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            lastSessionWindowsStore: {
                [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
            },
            startupRestore: startupSessionRestoreOwner
        )
        self.historySessionOwner = historySession

        let persistence = WindowSessionPersistenceCoordinator(
            persistence: persistenceService,
            scheduler: persistenceScheduler,
            history: historySession
        )
        self.persistence = persistence
        self.restoration = BrowserWindowSessionRestorationService(
            restoration: restoreService,
            extensions: browserManager.extensionsModule,
            profileSupport: browserManager,
            startupSessions: browserManager
        )
        self.activation = BrowserWindowActivationService(
            splitManager: browserManager.splitManager,
            sidebarPresentation: browserManager.chromeBundle
                .sidebarPresentationOwner,
            persistence: persistence,
            activePageRouting: browserManager.urlBarBundle
                .activePageRoutingOwner,
            findManager: browserManager.findManager,
            extensions: browserManager.extensionsModule,
            profileRouter: browserManager.sumiProfileRouter,
            profileSupport: browserManager,
            nowPlaying: browserManager.nativeNowPlayingController,
            backgroundMedia: browserManager.backgroundMediaOptimizationService
        )
    }
}
