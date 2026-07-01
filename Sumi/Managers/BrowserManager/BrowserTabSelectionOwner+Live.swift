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
                browserManager?.tabManager.tab(for: tabId)
            },
            ephemeralTab: { tabId, windowState in
                windowState.ephemeralTabs.first(where: { $0.id == tabId })
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            liveShortcutTabs: { [weak browserManager] windowId in
                browserManager?.tabManager.liveShortcutTabs(in: windowId) ?? []
            },
            updateActiveSplitSide: { [weak browserManager] tabId, windowId in
                browserManager?.splitManager.updateActiveSide(for: tabId, in: windowId)
            },
            syncWindowSpaceContext: { [weak browserManager] windowState, animateTheme in
                browserManager?.syncWindowSpaceContext(
                    in: windowState,
                    animateTheme: animateTheme
                )
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            updateWorkspaceTheme: { [weak browserManager] windowState, theme, animate in
                browserManager?.updateWorkspaceTheme(for: windowState, to: theme, animate: animate)
            },
            applySettingsSurfaceNavigation: { [weak browserManager] url in
                browserManager?.sumiSettings?.applyNavigationFromSettingsSurfaceURL(url)
            },
            canMaterializeNormalTabWebViewDuringStartup: { [weak browserManager] tab in
                browserManager?.canMaterializeNormalTabWebViewDuringStartup(tab) ?? true
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
                browserManager?.dismissFloatingBarAfterSelection(in: windowState)
            },
            updateFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.updateFindManagerCurrentTab()
            },
            clearFindManagerCurrentTab: { [weak browserManager] in
                browserManager?.findManager.updateCurrentTab(nil, in: nil)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            },
            runtimeNotifications: BrowserManagerRuntimeWiring.tabSelectionRuntimeNotifications(
                for: browserManager
            ),
            updateActiveTabState: { [weak browserManager] tab in
                browserManager?.tabManager.updateActiveTabState(tab)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            selectionTargetForSpaceActivation: { [weak browserManager] space, windowState in
                browserManager?.selectionTargetForSpaceActivation(
                    in: space,
                    windowState: windowState
                )
            },
            updateProfileRuntimeStates: { [weak browserManager] windowState in
                browserManager?.updateProfileRuntimeStates(activeWindowState: windowState)
            },
            showNewTabFloatingBar: { [weak browserManager] windowState in
                browserManager?.showNewTabFloatingBar(in: windowState)
            }
        )
    }
}
