import Foundation

@testable import Sumi

@MainActor
func makeTestSplitRuntimeMemberResolver(
    _ manager: BrowserManager
) -> SplitRuntimeMemberResolver {
    SplitRuntimeMemberResolver(
        membership: manager.splitGroupMembership,
        splitGroups: manager.splitGroupStore,
        regularTabs: manager.regularTabCollectionOwner,
        pins: manager.shortcutPinCollectionStateOwner,
        activation: manager.shortcutPresentationActivation
    )
}

@MainActor
func makeTestShortcutSplitLauncherDestinationResolver(
    _ manager: BrowserManager
) -> ShortcutSplitLauncherDestinationResolver {
    ShortcutSplitLauncherDestinationResolver(
        folders: manager.folderCollectionStateOwner,
        spacePinnedStructure: manager.spacePinnedStructureOwner
    )
}

@MainActor
func makeTestShortcutSplitLauncherPlacement(
    _ manager: BrowserManager
) -> ShortcutSplitLauncherPlacementService {
    let batches = ShortcutSplitLauncherMoveBatchStaging(
        catalog: ShortcutSplitLauncherCatalogTransaction(
            pinStore: manager.shortcutPinStoreOwner,
            pins: manager.shortcutPinCollectionStateOwner
        ),
        bindingStaging: ShortcutSplitLauncherBindingStaging(
            refreshes: manager.liveShortcutPresentationRefreshes,
            resolution: manager.shortcutPinRuntimeResolutionOwner,
            batches: ShortcutTabBindingBatchFactory(
                runtimeConnection: manager.runtimePortConnection,
                windowMutations: manager.shortcutWindowMutationOwner,
                profiles: manager.tabProfileTransitions,
                persistence: ShortcutSplitLauncherWindowPersistence(
                    structuralLookup: manager.structuralLookupCoordinator
                ),
                structuralLookup: manager.structuralLookupCoordinator
            )
        ),
        residenceMutations: manager.liveShortcutTabs.staging,
        structuralMutations: manager.structuralCollectionMutationOwner,
        structuralLookup: manager.structuralLookupCoordinator
    )
    return ShortcutSplitLauncherPlacementService(
        pins: manager.shortcutPinCollectionStateOwner,
        destinationResolver: makeTestShortcutSplitLauncherDestinationResolver(
            manager
        ),
        moves: ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: manager.shortcutWindowMutationOwner,
            folderOpenState: manager.folderOpenState
        )
    )
}

@MainActor
func makeTestShortcutSplitLauncherRelease(
    _ manager: BrowserManager
) -> ShortcutSplitLauncherReleasePlanner {
    ShortcutSplitLauncherReleasePlanner(
        pins: manager.shortcutPinCollectionStateOwner,
        destinationResolver: makeTestShortcutSplitLauncherDestinationResolver(
            manager
        )
    )
}

@MainActor
func makeTestWindowSplitPresentationSynchronizer(
    browser: BrowserManager,
    windows: @escaping @MainActor () -> [BrowserWindowState]
) -> WindowSplitPresentationSynchronizer {
    let manager = browser
    let members = makeTestSplitRuntimeMemberResolver(manager)
    let materialization = WindowSplitMaterializationService(
        query: WindowSplitMaterializationQuery(
            splitGroups: manager.splitGroupStore,
            regularTabs: manager.regularTabCollectionOwner,
            pins: manager.shortcutPinCollectionStateOwner,
            liveShortcuts: manager.liveShortcutTabs
        ),
        activation: manager.shortcutPresentationActivation,
        structuralLookup: manager.structuralLookupCoordinator
    )
    let preparation = WindowSplitPresentationPreparationService(
        drafts: WindowSplitPresentationDraftPlanner(
            splitGroups: manager.splitGroupStore,
            regularTabs: manager.regularTabCollectionOwner,
            pins: manager.shortcutPinCollectionStateOwner
        ),
        activation: manager.shortcutPresentationActivation,
        regularTabs: manager.regularTabCollectionOwner,
        validator: WindowSplitPresentationSettlementValidator(
            splitGroups: manager.splitGroupStore,
            regularTabs: manager.regularTabCollectionOwner,
            liveShortcuts: manager.liveShortcutTabs,
            currentWindows: windows
        ),
        windows: windows
    )
    return WindowSplitPresentationSynchronizer(
        preparation: preparation,
        splitGroups: manager.splitGroupStore,
        members: members,
        materialization: materialization,
        terminalEffects: WindowSplitPresentationEffectExecutor(
            selection: manager.browserTabSelection,
            updates: manager.splitUpdateChannel,
            visuals: manager.shellRuntime.windowVisuals,
            persistence: manager.windowSessionPersistenceCoordinator
        )
    )
}
