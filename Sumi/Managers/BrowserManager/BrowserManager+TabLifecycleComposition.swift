import Foundation

@MainActor
extension BrowserManager {
    func composeTabCloseFallbackPlanner() -> BrowserTabCloseFallbackPlanner {
        BrowserTabCloseFallbackPlanner(
            selectionService: shellRuntime.windowSelection,
            tabStore: runtimeStore
        )
    }

    func composeShortcutLiveTabClose() -> ShortcutLiveTabCloseService {
        let shellRuntime = shellRuntime
        let tabStore = runtimeStore
        let splitClose = ShortcutLiveTabSplitCloseTransaction(
            splitGroups: splitGroupStore,
            hostedUnload: splitShortcutHostedUnload
        )
        let standaloneClose = ShortcutLiveTabStandaloneCloseTransaction(
            tabStore: tabStore,
            structuralLookup: structuralLookupCoordinator,
            retirement: shortcutLiveTabRetirement,
            fallbackPlanner: tabCloseFallbackPlanner,
            splitMembership: splitGroupMembership,
            visuals: shellRuntime.windowVisuals
        )
        let publication = ShortcutLiveTabClosePublication(
            pins: shortcutPinCollectionStateOwner,
            recentlyClosed: recentlyClosedManager,
            notifications: notificationPresenter
        )
        return ShortcutLiveTabCloseService(
            tabStore: tabStore,
            splitClose: splitClose,
            standaloneClose: standaloneClose,
            publication: publication
        )
    }

    func composeTabCloseOrchestration() -> BrowserTabCloseOrchestrationOwner {
        let shellRuntime = shellRuntime
        return BrowserTabCloseOrchestrationOwner(
            context: BrowserCurrentTabCloseContext(
                windows: windowRegistry,
                tabs: shellRuntime.windowTabs
            ),
            glanceInterception: GlanceTabCloseInterception(
                glanceManager: glanceManager
            ),
            routing: BrowserTabCloseRouting(
                regularTabs: BrowserRegularTabCloseTransaction(
                    tabClosure: tabClosureService,
                    fallbackPlanner: tabCloseFallbackPlanner,
                    presentation: BrowserRegularTabClosePresentation(
                        selection: browserTabSelection,
                        visuals: shellRuntime.windowVisuals,
                        persistence: windowSessionPersistenceCoordinator
                    ),
                    residences: tabResidenceAuthority
                ),
                incognitoTabs: BrowserIncognitoTabCloseTransaction(
                    selection: browserTabSelection
                ),
                shortcutTabs: shortcutLiveTabClose
            ),
            residences: tabResidenceAuthority,
            notifications: notificationPresenter
        )
    }

    func composeTabOpening() -> BrowserTabOpeningOwner {
        let shellRuntime = shellRuntime
        let destinations = BrowserTabOpenDestinationResolver(
            spaces: spaceStateOwner,
            regularTabs: regularTabCollectionOwner,
            windows: windowRegistry,
            windowTabs: shellRuntime.windowTabs
        )
        let activation = BrowserTabOpenActivation(
            selection: browserTabSelection,
            startupProtection: startupProtectionRuntime,
            membership: tabCollectionMembershipOwner,
            windows: windowRegistry
        )
        return BrowserTabOpeningOwner(
            destinations: destinations,
            regularTabs: BrowserRegularTabOpeningTransaction(
                lifecycle: regularTabLifecycleOwner,
                tabFactory: tabFactory,
                destinations: destinations,
                activation: activation
            ),
            ephemeralTabs: BrowserEphemeralTabOpeningTransaction(
                lifecycle: ephemeralLifecycleOwner,
                settings: settingsState,
                activation: activation
            ),
            activation: activation
        )
    }
}
