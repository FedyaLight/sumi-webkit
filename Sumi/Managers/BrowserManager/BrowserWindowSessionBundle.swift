//
//  BrowserWindowSessionBundle.swift
//  Sumi
//
//  Phase 5A / N2 capability bag: window session, tab context, visual mutation,
//  window-scoped navigation, restore, and shell commands.
//

import Foundation

/// Groups window-session owners and the Phase 4C window-session command façade.
/// `WindowSessionService` stays on BrowserManager so tests can replace the
/// session key / service before the bag's lazy owners are first touched.
@MainActor
final class BrowserWindowSessionBundle {
    let commands: BrowserWindowSessionCommands
    let spaceStateOwner: BrowserWindowSpaceStateOwner
    let tabContextOwner: BrowserWindowTabContextOwner
    let visualMutationOwner: BrowserWindowVisualMutationOwner
    let scopedNavigationOwner: BrowserWindowScopedNavigationOwner
    let activationOwner: BrowserWindowSessionActivationOwner
    let historySessionOwner: BrowserWindowHistorySessionOwner
    let recentlyClosedRestoreOwner: BrowserRecentlyClosedRestoreOwner
    let windowStateValidationOwner: BrowserWindowStateValidationOwner

    init(
        browserManager: BrowserManager,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    ) {
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
                browserManager?.windowSessionBundle.activationOwner.persistWindowSession(for: windowState)
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
                browserManager?.webViewCoordinator?.hasActiveHistorySwipe(in: windowId) == true
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowId in
                browserManager?.webViewCoordinator?.performImmediateVisualHandoffIfPossible(
                    in: windowId
                ) ?? false
            },
            prepareVisibleWebViews: { [weak browserManager] windowState in
                guard let browserManager else { return false }
                return browserManager.shellRuntime.requireWebViewCoordinator().prepareVisibleWebViews(
                    for: windowState
                )
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                guard let browserManager else { return }
                browserManager.shellRuntime.requireWebViewCoordinator().schedulePrepareVisibleWebViews(
                    for: windowState
                )
            }
        )
        self.scopedNavigationOwner = BrowserWindowScopedNavigationOwner(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            reloadTab: { [weak browserManager] tabId, windowId in
                browserManager?.webViewRoutingService.reloadTab(tabId, in: windowId)
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
                browserManager?.tabManager.lastSessionRestoreOwner.mergeSnapshotForLastSessionRestore(snapshot)
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
        self.historySessionOwner = BrowserWindowHistorySessionOwner(
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            makeWindowSessionSnapshot: { [weak browserManager] windowState in
                guard let browserManager else { return nil }
                return browserManager.windowSessionService.makeWindowSessionSnapshot(
                    for: windowState,
                    runtime: WindowSessionRuntimeFactory.make(for: browserManager)
                )
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
        let windowSessionService = browserManager.windowSessionService
        let nativeNowPlayingController = browserManager.nativeNowPlayingController
        let backgroundMediaOptimizationService = browserManager.backgroundMediaOptimizationService
        let permissionRuntime = browserManager.permissionRuntime
        self.activationOwner = BrowserWindowSessionActivationOwner(
            windowSessionService: windowSessionService,
            runtime: { [weak browserManager] in
                browserManager.map { WindowSessionRuntimeFactory.make(for: $0) }
            },
            refreshSplitPublishedState: { [weak browserManager] windowId in
                browserManager?.splitManager.refreshPublishedState(for: windowId)
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.updateFindManagerCurrentTab()
            },
            notifyExtensionWindowOpened: { [weak browserManager] windowState in
                browserManager?.extensionsModule.notifyWindowOpenedIfLoaded(windowState)
            },
            notifyExtensionWindowFocused: { [weak browserManager] windowState in
                browserManager?.extensionsModule.notifyWindowFocusedIfLoaded(windowState)
            },
            reconcileStartupSessionIfPossible: { [weak browserManager] in
                browserManager?.reconcileStartupSessionIfPossible()
            },
            adoptProfileForWindowActivation: { [weak browserManager] windowState in
                browserManager?.adoptProfileIfNeeded(for: windowState, context: .windowActivation)
            },
            scheduleNativeNowPlayingRefresh: { delayNanoseconds in
                nativeNowPlayingController.scheduleRefresh(delayNanoseconds: delayNanoseconds)
            },
            scheduleBackgroundMediaReconcile: { reason in
                backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: {
                permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: {
                permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            },
            refreshLastSessionWindowsStore: { [weak browserManager] in
                browserManager?.windowSessionBundle.historySessionOwner.refreshLastSessionWindowsStore(excludingWindowID: nil)
            }
        )
    }
}
