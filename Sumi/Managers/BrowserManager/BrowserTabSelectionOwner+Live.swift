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
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            liveShortcutTabs: { [weak browserManager] windowId in
                browserManager?.tabManager.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            updateActiveSplitSide: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
            },
            syncWindowSpaceContext: { [weak browserManager] windowState, animateTheme in
                browserManager?.windowSpaceStateOwner.syncWindowSpaceContext(
                    in: windowState,
                    animateTheme: animateTheme
                )
            },
            space: { [weak browserManager] spaceId in
                browserManager?.windowSpaceStateOwner.space(for: spaceId)
            },
            updateWorkspaceTheme: { [weak browserManager] windowState, theme, animate in
                browserManager?.workspaceThemeTransitionOwner.updateWorkspaceTheme(for: windowState, to: theme, animate: animate)
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
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
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
                browserManager?.floatingBarRoutingOwner.dismissFloatingBarAfterSelection(in: windowState)
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.findBarRoutingOwner.updateCurrentTab()
            },
            clearFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.findManager.updateCurrentTab(nil, in: nil)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.refreshCompositor(for: windowState)
            },
            runtimeNotifications: BrowserManagerRuntimeWiring.tabSelectionRuntimeNotifications(
                for: browserManager
            ),
            updateActiveTabState: { [weak browserManager] tab in
                browserManager?.tabManager.activeSelectionOwner.updateActiveTabState(tab)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.persistWindowSession(for: windowState)
            },
            selectionTargetForSpaceActivation: { [weak browserManager] space, windowState in
                browserManager?.windowSpaceStateOwner.selectionTargetForSpaceActivation(
                    in: space,
                    windowState: windowState
                )
            },
            updateProfileRuntimeStates: { [weak browserManager] windowState in
                browserManager?.windowSpaceStateOwner.updateProfileRuntimeStates(activeWindowState: windowState)
            },
            showNewTabFloatingBar: { [weak browserManager] windowState in
                browserManager?.floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
            }
        )
    }
}
