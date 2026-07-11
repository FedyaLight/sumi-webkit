import Foundation

extension BrowserTabSelectionOwner {
    static func liveActions(for browserManager: BrowserManager) -> Actions {
        Actions(
            activeWindowId: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow?.id
            },
            window: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            ephemeralTab: { tabId, windowState in
                windowState.ephemeralTabs.first(where: { $0.id == tabId })
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            liveShortcutTabs: { [weak browserManager] windowId in
                browserManager?.tabManager.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            updateActiveSplitSide: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
            },
            syncWindowSpaceContext: { [weak browserManager] windowState in
                browserManager?.windowStateReconciler.synchronizeSpaceContext(
                    in: windowState
                )
            },
            space: { [weak browserManager] spaceId in
                spaceId.flatMap {
                    browserManager?.tabManager.spaceStateOwner.space(with: $0)
                }
            },
            updateWorkspaceTheme: { [weak browserManager] windowState, theme, animate in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner.updateWorkspaceTheme(for: windowState, to: theme, animate: animate)
            },
            applySettingsSurfaceNavigation: { [weak browserManager] url in
                browserManager?.sumiSettings?.applyNavigationFromSettingsSurfaceURL(url)
            },
            canMaterializeWebViewDuringStartup: { [weak browserManager] tab in
                browserManager?.startupProtectionRuntime.canMaterializeWebViewDuringStartup(tab) ?? true
            },
            markTabAccessed: { [weak browserManager] tabId in
                browserManager?.compositorManager.markTabAccessed(tabId)
            },
            ensureVisibleWebView: { [weak browserManager] tab, windowID in
                guard let browserManager else {
                    tab.loadWebViewIfNeeded()
                    return
                }
                guard browserManager.webViewOwnershipQuery.webView(
                    for: tab.id,
                    in: windowID
                ) == nil else {
                    return
                }
                guard let ownershipService = browserManager.webViewOwnershipService else {
                    tab.loadWebViewIfNeeded()
                    return
                }
                _ = ownershipService.webView(for: tab, in: windowID)
            },
            handleNativeNowPlayingTabActivated: { [weak browserManager] tabId in
                browserManager?.nativeNowPlayingController.handleTabActivated(tabId)
            },
            scheduleNativeNowPlayingRefresh: { [weak browserManager] delayNanoseconds in
                browserManager?.nativeNowPlayingController.scheduleRefresh(delayNanoseconds: delayNanoseconds)
            },
            fetchVisibleFavicon: { tab in
                Task { @MainActor [weak tab] in
                    guard let tab else { return }
                    await tab.fetchFaviconForVisiblePresentation()
                }
            },
            dismissFloatingBarAfterSelection: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.floatingBar.presentation
                    .dismissAfterSelection(in: windowState)
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.updateFindManagerCurrentTab()
            },
            clearFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.findManager.updateCurrentTab(nil, in: nil)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            },
            runtimeNotifications: BrowserManagerRuntimeWiring.tabSelectionRuntimeNotifications(
                for: browserManager
            ),
            updateActiveTabState: { [weak browserManager] tab in
                browserManager?.tabManager.activeSelectionOwner.updateActiveTabState(tab)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            selectionTargetForSpaceActivation: { [weak browserManager] space, windowState in
                browserManager?.shellRuntime.windowTabs.selectionTarget(
                    for: space,
                    in: windowState
                )
            }
        )
    }
}
