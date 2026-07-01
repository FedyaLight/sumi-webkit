import Foundation
import WebKit

@MainActor
enum BrowserGlanceRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> GlanceManager.Runtime {
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
                return makePreviewTab(
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

    private static func targetSpace(
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
}
