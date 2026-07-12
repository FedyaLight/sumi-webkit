import Foundation
import WebKit

@MainActor
enum BrowserGlanceRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> GlanceManager.Runtime {
        let splitQuery = browserManager.splitComposition.query
        let emptySplitCreation = browserManager.splitComposition.emptyCreation
        let webViewCompositor = browserManager.webViewRuntime.compositorRuntime
        let untrackedMaterialization = browserManager.webViewRuntime
            .untrackedWebViewMaterialization
        let detachedCleanup = browserManager.webViewRuntime.detachedWebViewCleanup
        let tabBrowserRuntime = TabBrowserRuntimeFactory.make(for: browserManager)

        return GlanceManager.Runtime(
            windowStateContainingTab: { [weak browserManager] in
                browserManager?.shellRuntime.windowTabs.windowState(containing: $0)
            },
            hasLoadedInitialTabData: { [weak browserManager] in browserManager?.tabManager.startupRestoreLifecycle.hasLoadedInitialData ?? false },
            tab: { [weak browserManager] in browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: $0) },
            shortcutPin: { [weak browserManager] in browserManager?.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: $0) },
            shortcutLiveTab: { [weak browserManager] in browserManager?.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: $0, in: $1) },
            activateShortcutPin: { [weak browserManager] in
                browserManager?.tabManager.shortcutTabMaterializer.materialize($0, in: $1, currentSpaceId: $2)
            },
            currentTab: { [weak browserManager] in browserManager?.shellRuntime.windowTabs.currentTab(for: $0) },
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
            visibleSplitTabCount: { [splitQuery] in
                splitQuery.visibleTabIDs(in: $0).count
            },
            dismissFloatingBarIfVisible: { [weak browserManager] in
                browserManager?.urlBarBundle.floatingBar.presentation
                    .dismissIfVisible(in: $0, preserveDraft: true) ?? false
            },
            isFindBarVisible: { [weak browserManager] in browserManager?.findManager.isFindBarVisible ?? false },
            findCurrentTabId: { [weak browserManager] in browserManager?.findManager.currentTab?.id },
            hideFindBar: { [weak browserManager] in browserManager?.findManager.hideFindBar() },
            updateFindManagerCurrentTab: { [weak browserManager] in browserManager?.updateFindManagerCurrentTab() },
            persistWindowSession: { [weak browserManager] in browserManager?.windowSessionBundle.persistence.persist($0) },
            makePreviewTab: { [weak browserManager] url, sourceTab, windowState in
                guard let browserManager else { return nil }
                return makePreviewTab(
                    for: url,
                    sourceTab: sourceTab,
                    windowState: windowState,
                    browserManager: browserManager,
                    tabBrowserRuntime: tabBrowserRuntime
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
            selectPromotedTab: { [weak browserManager] in browserManager?.selectTab($0, in: $1) },
            selectPromotedTabInActiveWindow: { [weak browserManager] in browserManager?.selectTab($0) },
            createSplitPlaceholder: { [emptySplitCreation] windowState in
                emptySplitCreation.create(
                    side: .right,
                    in: windowState,
                    reason: .splitTabPicker
                )
            },
            registerPromotedHost: { [webViewCompositor] host, tabId, windowId, attachmentCompletion in
                webViewCompositor.registerPromotedHost(
                    host,
                    for: tabId,
                    in: windowId,
                    attachmentCompletion: attachmentCompletion
                )
            },
            previewWebView: { [weak browserManager] in browserManager?.webViewRoutingService.anyLiveWebView(for: $0) },
            ensurePreviewWebView: { [untrackedMaterialization] tab, _ in
                untrackedMaterialization.webView(for: tab)
            },
            ownsPreviewWebView: { [weak browserManager] in browserManager?.webViewRoutingService.ownsLiveWebView($1, for: $0) ?? false },
            releasePreviewWebView: { [detachedCleanup] in
                detachedCleanup.releaseUntracked(for: $0)
            }
        )
    }

    private static func makePreviewTab(
        for url: URL,
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        browserManager: BrowserManager,
        tabBrowserRuntime: TabBrowserRuntime
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
        tab.attachBrowserRuntime(tabBrowserRuntime)
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
