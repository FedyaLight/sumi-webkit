import Foundation
import WebKit

@MainActor
enum BrowserGlanceRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> GlanceManager.Runtime {
        GlanceManager.Runtime(
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowSessionBundle.tabContextOwner.windowState(containing: tab)
            },
            hasLoadedInitialTabData: { [weak browserManager] in
                browserManager?.tabManager.startupRestoreLifecycle.hasLoadedInitialData ?? false
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            shortcutPin: { [weak browserManager] pinId in
                browserManager?.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
            },
            shortcutLiveTab: { [weak browserManager] pinId, windowId in
                browserManager?.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowId)
            },
            activateShortcutPin: { [weak browserManager, tabFactory = browserManager.tabManager.tabFactory] pin, windowId, currentSpaceId in
                guard let browserManager else {
                    return tabFactory.makeTab(url: pin.launchURL, name: pin.title)
                }
                return browserManager.tabManager.shortcutLiveTabOwner.activateShortcutPin(
                    pin,
                    in: windowId,
                    currentSpaceId: currentSpaceId
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
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
                browserManager?.urlBarBundle.floatingBarRoutingOwner.dismissFloatingBarIfVisible(
                    in: windowId,
                    preserveDraft: true
                ) ?? false
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
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            makePreviewTab: { [weak browserManager, tabFactory = browserManager.tabManager.tabFactory] url, sourceTab, windowState in
                guard let browserManager else {
                    return tabFactory.makeTab(
                        url: url,
                        name: url.host ?? "Glance",
                        favicon: "globe",
                        index: 0
                    )
                }
                return makePreviewTab(
                    for: url,
                    sourceTab: sourceTab,
                    windowState: windowState,
                    browserManager: browserManager
                )
            },
            adoptPreviewTab: { [weak browserManager] previewTab, sourceTab, windowState in
                guard let browserManager else { return previewTab }
                return browserManager.tabManager.regularTabLifecycleOwner.adoptGlanceTab(
                    previewTab,
                    sourceTab: sourceTab,
                    in: targetSpace(
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
                return webViewCoordinator.compositorRuntime.registerPromotedHost(
                    host,
                    for: tabId,
                    in: windowId,
                    attachmentCompletion: attachmentCompletion
                )
            },
            previewWebView: { [weak browserManager] tab in
                browserManager?.webViewRoutingService.anyLiveWebView(for: tab)
            },
            ensurePreviewWebView: { [weak browserManager] tab, _ in
                browserManager?.webViewOwnershipService?.ensureUntracked(for: tab)
            },
            ownsPreviewWebView: { [weak browserManager] tab, webView in
                browserManager?.webViewRoutingService.ownsLiveWebView(webView, for: tab) ?? false
            },
            releasePreviewWebView: { [weak browserManager] tab in
                browserManager?.webViewOwnershipService?.releaseUntracked(for: tab)
            }
        )
    }

    private static func makePreviewTab(
        for url: URL,
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        browserManager: BrowserManager
    ) -> Tab {
        let sourceProfile = sourceTab?.resolveProfile()
        let targetSpace = targetSpace(
            sourceTab: sourceTab,
            windowState: windowState,
            browserManager: browserManager
        )

        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: url,
            name: url.host ?? "Glance",
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.profileId = sourceProfile?.id ?? targetSpace?.profileId ?? browserManager.currentProfile?.id
        return tab
    }

    private static func targetSpace(
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        browserManager: BrowserManager
    ) -> Space? {
        windowState?.currentSpaceId.flatMap { spaceId in
            browserManager.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId })
        }
        ?? sourceTab?.spaceId.flatMap { spaceId in
            browserManager.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId })
        }
    }
}
