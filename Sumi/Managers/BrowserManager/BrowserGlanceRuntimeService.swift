import Foundation
import WebKit

@MainActor
enum BrowserGlanceRuntimeService {
    static func runtime(
        for browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> GlanceManager.Runtime {
        let emptySplitCreation = browserManager.splitEmptyCreation
        let webViewCompositor = browserManager.webViewRuntime.compositorRuntime
        let untrackedMaterialization = browserManager.webViewRuntime
            .untrackedWebViewMaterialization
        let detachedCleanup = browserManager.webViewRuntime.detachedWebViewCleanup
        let tabBrowserRuntime = TabBrowserRuntimeFactory.make(for: browserManager)
        let windowTabs = browserManager.shellRuntime.windowTabs
        let startupRestore = browserManager.startupRestoreLifecycle
        let membership = browserManager
            .tabCollectionMembershipOwner
        let pins = browserManager.shortcutPinCollectionStateOwner
        let shortcutActivation = browserManager
            .shortcutPresentationActivation
        let regularLifecycle = browserManager
            .regularTabLifecycleOwner
        let spaces = browserManager.spaceStateOwner
        let tabFactory = browserManager.tabFactory
        let profileAdmission = browserManager.profileReferenceAdmission
        let currentProfile = browserManager.currentProfileAuthority

        return GlanceManager.Runtime(
            windowStateContainingTab: { [windowTabs] in
                windowTabs.windowState(containing: $0)
            },
            hasLoadedInitialTabData: { [startupRestore] in
                startupRestore.hasLoadedInitialData
            },
            tab: { [membership] in membership.tab(for: $0) },
            shortcutPin: { [pins] in pins.shortcutPin(by: $0) },
            activateShortcutPin: { [shortcutActivation] in
                shortcutActivation.activate(
                    $0,
                    in: $1,
                    presentationSpaceID: $2
                )
            },
            currentTab: { [windowTabs] in windowTabs.currentTab(for: $0) },
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
            dismissCommandPaletteIfVisible: { [weak browserManager] in
                browserManager?.urlBarBundle.commandPalettePresentation
                    .dismissIfVisible(in: $0, preserveDraft: true) ?? false
            },
            isFindBarVisible: { [weak browserManager] in browserManager?.findManager.isFindBarVisible ?? false },
            findCurrentTabId: { [weak browserManager] in browserManager?.findManager.currentTab?.id },
            hideFindBar: { [weak browserManager] in browserManager?.findManager.hideFindBar() },
            updateFindManagerCurrentTab: { [weak browserManager] in browserManager?.updateFindManagerCurrentTab() },
            persistWindowSession: { [weak browserManager] in
                browserManager?.windowSessionPersistenceCoordinator.persist($0)
            },
            withPreparedPreviewTab: {
                [
                    spaces,
                    tabFactory,
                    profileAdmission,
                    currentProfile,
                    tabBrowserRuntime
                ] url, sourceTab, windowState, publish in
                return withPreparedPreviewTab(
                    for: url,
                    sourceTab: sourceTab,
                    windowState: windowState,
                    spaces: spaces,
                    tabFactory: tabFactory,
                    profileAdmission: profileAdmission,
                    currentProfile: currentProfile,
                    tabBrowserRuntime: tabBrowserRuntime,
                    publish: publish
                )
            },
            adoptPreviewTab: { [regularLifecycle, spaces] previewTab, sourceTab, windowState in
                regularLifecycle.adoptGlanceTab(
                    previewTab,
                    sourceTab: sourceTab,
                    in: targetSpace(
                        sourceTab: sourceTab,
                        windowState: windowState,
                        spaces: spaces
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

    private static func withPreparedPreviewTab(
        for url: URL,
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        spaces: TabSpaceCollectionStateOwner,
        tabFactory: TabFactory,
        profileAdmission: ProfileReferenceAdmissionLedger,
        currentProfile: BrowserCurrentProfileAuthority,
        tabBrowserRuntime: TabBrowserRuntime,
        publish: @MainActor (Tab) -> Bool
    ) -> Bool {
        let targetSpace = targetSpace(
            sourceTab: sourceTab,
            windowState: windowState,
            spaces: spaces
        )
        let profileID = sourceTab?.resolveProfile()?.id
            ?? targetSpace?.profileId
            ?? currentProfile.currentProfile?.id
        let referencedProfileIDs = Set(profileID.map { [$0] } ?? [])
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileAdmission.beginReferenceMutation(
                to: referencedProfileIDs
            )
        } catch {
            return false
        }
        defer {
            precondition(
                profileAdmission.endReferenceMutation(lease),
                "Glance preview publication lost its profile-reference mutation lease"
            )
        }

        let tab = tabFactory.makeTab(
            url: url,
            name: url.host ?? "Glance",
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0
        )
        tab.profileId = profileID
        tab.attachBrowserRuntime(tabBrowserRuntime)
        guard profileAdmission.validate(lease, covers: referencedProfileIDs) else {
            return false
        }
        return publish(tab)
    }

    private static func targetSpace(
        sourceTab: Tab?,
        windowState: BrowserWindowState?,
        spaces: TabSpaceCollectionStateOwner
    ) -> Space? {
        windowState?.currentSpaceId.flatMap { spaceId in
            spaces.space(with: spaceId)
        }
        ?? sourceTab?.spaceId.flatMap { spaceId in
            spaces.space(with: spaceId)
        }
    }
}
