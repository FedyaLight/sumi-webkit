import Foundation
import WebKit

@MainActor
enum BrowserGlanceRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> GlanceManager.Runtime {
        GlanceManager.Runtime(
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
            visibleSplitTabCount: { [weak browserManager] in browserManager?.splitManager.visibleTabIds(for: $0).count ?? 0 },
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
            selectPromotedTab: { [weak browserManager] in browserManager?.selectTab($0, in: $1) },
            selectPromotedTabInActiveWindow: { [weak browserManager] in browserManager?.selectTab($0) },
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
            previewWebView: { [weak browserManager] in browserManager?.webViewRoutingService.anyLiveWebView(for: $0) },
            ensurePreviewWebView: { [weak browserManager] tab, _ in browserManager?.webViewOwnershipService?.ensureUntracked(for: tab) },
            ownsPreviewWebView: { [weak browserManager] in browserManager?.webViewRoutingService.ownsLiveWebView($1, for: $0) ?? false },
            releasePreviewWebView: { [weak browserManager] in browserManager?.webViewOwnershipService?.releaseUntracked(for: $0) }
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
