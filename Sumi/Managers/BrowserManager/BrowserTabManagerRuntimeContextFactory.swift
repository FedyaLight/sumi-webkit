import Foundation

@MainActor
enum BrowserTabManagerRuntimeContextFactory {
    static func runtime(for browserManager: BrowserManager) -> TabManagerRuntimeContext {
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
            webViewLifecycle: BrowserTabManagerWebViewLifecycleFactory.service(for: browserManager),
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
                captureClosedTab(tab, sourceSpaceId: sourceSpaceId, browserManager: browserManager)
            },
            captureDeletedShortcutLauncher: { [weak browserManager] pin in
                browserManager?.recentlyClosedManager.captureDeletedShortcutLauncher(pin)
            },
            presentTabClosureToast: { [weak browserManager] tabCount in
                browserManager?.toastPresenter.presentTabClosureToast(tabCount: tabCount)
            },
            validateWindowStates: { [weak browserManager] in
                browserManager?.windowSpaceStateOwner.validateWindowStates()
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.persistWindowSession(for: windowState)
            },
            syncWorkspaceThemeAcrossWindows: { [weak browserManager] space, animate in
                browserManager?.workspaceThemeTransitionOwner.syncWorkspaceThemeAcrossWindows(for: space, animate: animate)
            },
            closeAuxiliaryMiniWindow: { [weak browserManager] tab, reason in
                browserManager?.webViewCloseRouter.closeAuxiliaryMiniWindow(for: tab, reason: reason)
            },
            isLiveFolder: { [weak browserManager] folderId in
                browserManager?.liveFolderManager.isLiveFolder(folderId) == true
            },
            deleteLiveFolderState: { [weak browserManager] folderIds in
                browserManager?.liveFolderManager.deleteState(forFolderIds: folderIds)
            }
        )
    }

    private static func captureClosedTab(
        _ tab: Tab,
        sourceSpaceId: UUID?,
        browserManager: BrowserManager?
    ) {
        browserManager?.recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: sourceSpaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }
}

extension TabManagerRuntimeContext {
    static func live(browserManager: BrowserManager) -> TabManagerRuntimeContext {
        BrowserTabManagerRuntimeContextFactory.runtime(for: browserManager)
    }
}
