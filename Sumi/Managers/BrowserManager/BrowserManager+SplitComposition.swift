import Foundation

@MainActor
extension BrowserManager {
    func composeSplitPreviews() -> SplitPreviewSession {
        let windowRegistry = windowRegistry
        return SplitPreviewSession(
            publishWindowChange: { [splitUpdateChannel] in
                splitUpdateChannel.publish(windowID: $0)
            },
            refreshWindow: { [weak self, windowRegistry] windowID in
                guard let self,
                      let window = windowRegistry.windows[windowID] else {
                    return
                }
                shellRuntime.windowVisuals.refreshCompositor(for: window)
            }
        )
    }

    func composeSplitQuery() -> WindowSplitQuery {
        let windowRegistry = windowRegistry
        return WindowSplitQuery(
            splitGroups: splitGroupStore,
            regularTabs: regularTabCollectionOwner,
            pins: shortcutPinCollectionStateOwner,
            liveShortcuts: liveShortcutTabs,
            windows: windowRegistry,
            previewIsActive: { [splitPreviews] in
                splitPreviews.isActive(in: $0)
            }
        )
    }

    func composeSplitMembers() -> SplitRuntimeMemberResolver {
        SplitRuntimeMemberResolver(
            membership: splitGroupMembership,
            splitGroups: splitGroupStore,
            regularTabs: regularTabCollectionOwner,
            pins: shortcutPinCollectionStateOwner,
            activation: shortcutPresentationActivation
        )
    }

    func composeSplitMaterialization() -> WindowSplitMaterializationService {
        WindowSplitMaterializationService(
            query: WindowSplitMaterializationQuery(
                splitGroups: splitGroupStore,
                regularTabs: regularTabCollectionOwner,
                pins: shortcutPinCollectionStateOwner,
                liveShortcuts: liveShortcutTabs
            ),
            activation: shortcutPresentationActivation,
            structuralLookup: structuralLookupCoordinator
        )
    }

    func composeSplitPresentations() -> WindowSplitPresentationSynchronizer {
        let windowRegistry = windowRegistry
        let windows: @MainActor () -> [BrowserWindowState] = {
            [windowRegistry] in
            Array(windowRegistry.windows.values)
        }
        return WindowSplitPresentationSynchronizer(
            preparation: WindowSplitPresentationPreparationService(
                drafts: WindowSplitPresentationDraftPlanner(
                    splitGroups: splitGroupStore,
                    regularTabs: regularTabCollectionOwner,
                    pins: shortcutPinCollectionStateOwner
                ),
                activation: shortcutPresentationActivation,
                regularTabs: regularTabCollectionOwner,
                validator: WindowSplitPresentationSettlementValidator(
                    splitGroups: splitGroupStore,
                    regularTabs: regularTabCollectionOwner,
                    liveShortcuts: liveShortcutTabs,
                    currentWindows: windows
                ),
                windows: windows
            ),
            splitGroups: splitGroupStore,
            members: splitMembers,
            materialization: splitMaterialization,
            terminalEffects: WindowSplitPresentationEffectExecutor(
                selection: browserTabSelection,
                updates: splitUpdateChannel,
                visuals: shellRuntime.windowVisuals,
                persistence: windowSessionPersistenceCoordinator
            )
        )
    }

    func composeSplitLauncherPlacement() -> ShortcutSplitLauncherPlacementService {
        let destinationResolver = ShortcutSplitLauncherDestinationResolver(
            folders: folderCollectionStateOwner,
            spacePinnedStructure: spacePinnedStructureOwner
        )
        let moveBatches = ShortcutSplitLauncherMoveBatchStaging(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: shortcutPinStoreOwner,
                pins: shortcutPinCollectionStateOwner
            ),
            bindingStaging: ShortcutSplitLauncherBindingStaging(
                refreshes: liveShortcutPresentationRefreshes,
                resolution: shortcutPinRuntimeResolutionOwner,
                batches: ShortcutTabBindingBatchFactory(
                    runtimeConnection: runtimePortConnection,
                    windowMutations: shortcutWindowMutationOwner,
                    profiles: tabProfileTransitions,
                    persistence: ShortcutSplitLauncherWindowPersistence(
                        structuralLookup: structuralLookupCoordinator
                    ),
                    structuralLookup: structuralLookupCoordinator
                )
            ),
            residenceMutations: liveShortcutTabs.staging,
            structuralMutations: structuralCollectionMutationOwner,
            structuralLookup: structuralLookupCoordinator
        )
        return ShortcutSplitLauncherPlacementService(
            pins: shortcutPinCollectionStateOwner,
            destinationResolver: destinationResolver,
            moves: ShortcutSplitLauncherMoveTransaction(
                batches: moveBatches,
                windowMutations: shortcutWindowMutationOwner,
                folderOpenState: folderOpenState
            )
        )
    }

    func composeSplitLauncherRelease() -> ShortcutSplitLauncherReleasePlanner {
        ShortcutSplitLauncherReleasePlanner(
            pins: shortcutPinCollectionStateOwner,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folders: folderCollectionStateOwner,
                spacePinnedStructure: spacePinnedStructureOwner
            )
        )
    }

    func composeSplitDissolution() -> SplitGroupDissolutionService {
        SplitGroupDissolutionService(
            splitGroups: splitGroupStore,
            mutations: splitGroupMutations,
            launcherPlacement: splitLauncherPlacement,
            presentations: splitPresentations
        )
    }

    func composeSplitWeightMutations() -> SplitLayoutWeightMutationService {
        SplitLayoutWeightMutationService(
            splitGroups: splitGroupStore,
            persistence: structuralPersistence
        )
    }

    func composeSplitDropTargets() -> SplitDropTargetService {
        let windowRegistry = windowRegistry
        return SplitDropTargetService(
            splitGroups: splitGroupStore,
            windowState: { [windowRegistry] in windowRegistry.windows[$0] },
            currentTab: { [weak self] in
                self?.shellRuntime.windowTabs.currentTab(for: $0)
            },
            query: splitQuery,
            memberResolver: splitMembers
        )
    }

    func composeSplitPlaceholderRetirement()
        -> EmptySplitPlaceholderRetirementService {
        EmptySplitPlaceholderRetirementService(
            regularTabs: regularTabCollectionOwner,
            structuralLookup: structuralLookupCoordinator,
            persistence: structuralPersistence,
            runtimeConnection: runtimePortConnection,
            runtimeCleanup: RegularTabClosureRuntimeCleanup(
                membership: tabCollectionMembershipOwner
            )
        )
    }

    func composeSplitPlaceholderReplacements()
        -> SplitPlaceholderReplacementPlanner {
        SplitPlaceholderReplacementPlanner(
            query: SplitPlaceholderReplacementQuery(
                regularTabs: regularTabCollectionOwner,
                splitGroups: splitGroupStore,
                membership: splitGroupMembership,
                liveShortcuts: liveShortcutTabs,
                members: splitMembers
            ),
            launcherRelease: splitLauncherRelease,
            splitMutations: splitGroupMutations,
            retirement: splitPlaceholderRetirement,
            presentations: splitPresentations
        )
    }

    func composeSplitDrops() -> SplitDropService {
        SplitDropService(
            topology: SplitDropTopologyTransaction(
                structuralLookup: structuralLookupCoordinator,
                membership: splitGroupMembership,
                splitGroups: splitGroupStore,
                mutations: splitGroupMutations,
                launcherPlacement: splitLauncherPlacement
            ),
            memberResolver: splitMembers,
            regularShortcutSidebarDrop: RegularTabShortcutSidebarDropTransaction(
                conversion: regularTabShortcutConversion,
                launcherPlacement: splitLauncherPlacement,
                presentations: splitPresentations
            ),
            presentations: splitPresentations,
            notifyLimit: { [weak self] in
                self?.notificationPresenter.presentSplitViewLimitNotification(
                    in: $0
                )
            }
        )
    }

    func composeSplitInsertion() -> SplitInsertionService {
        SplitInsertionService(
            currentTab: { [weak self] in
                self?.shellRuntime.windowTabs.currentTab(for: $0)
            },
            memberIsGrouped: { [splitGroupStore] in
                splitGroupStore.group(containing: $0) != nil
            },
            members: splitMembers,
            drops: splitDrops
        )
    }

    func composeSplitShortcutMemberRestoration()
        -> SplitShortcutMemberRestoreService {
        SplitShortcutMemberRestoreService(
            preparation: SplitShortcutMemberRestorePreparationService(
                splitGroups: splitGroupStore,
                pins: shortcutPinCollectionStateOwner,
                liveShortcuts: liveShortcutTabs,
                runtimeConnection: runtimePortConnection,
                launcherPlacement: splitLauncherPlacement
            ),
            splitMutations: splitGroupMutations,
            shortcutRetirement: shortcutLiveTabRetirement,
            publication: SplitShortcutMemberRestorePublication(
                presentations: splitPresentations,
                folderOpenState: folderOpenState,
                visuals: shellRuntime.windowVisuals
            )
        )
    }

    func composeSplitShortcutHostedUnload() -> ShortcutHostedSplitUnloadService {
        ShortcutHostedSplitUnloadService(
            runtimeConnection: runtimePortConnection,
            splitGroups: splitGroupStore,
            retirement: shortcutLiveTabRetirement,
            fallback: ShortcutHostedSplitFallbackQuery(
                spaces: spaceStateOwner,
                regularTabs: regularTabCollectionOwner
            ),
            visuals: shellRuntime.windowVisuals
        )
    }

    func composeSplitShortcutFocus() -> SplitShortcutFocusService {
        let shellRuntime = shellRuntime
        return SplitShortcutFocusService(
            runtimeConnection: runtimePortConnection,
            splitGroups: splitGroupStore,
            materialization: splitMaterialization,
            presentation: SplitShortcutFocusPresentationService(
                selection: browserTabSelection,
                visuals: shellRuntime.windowVisuals,
                persistence: windowSessionPersistenceCoordinator
            )
        )
    }

    func composeSplitLayout() -> SplitLayoutService {
        SplitLayoutService(
            topology: SplitLayoutTopologyTransaction(
                splitGroups: splitGroupStore,
                mutations: splitGroupMutations,
                regularTabs: regularTabCollectionOwner,
                launcherPlacement: splitLauncherPlacement
            ),
            query: splitQuery,
            weightMutations: splitWeightMutations,
            presentations: splitPresentations,
            dissolution: splitDissolution,
            restoreShortcutMember: { [splitShortcutMemberRestoration] in
                splitShortcutMemberRestoration.restoreShortcutSplitMember(
                    $0,
                    from: $1,
                    in: $2
                )
            }
        )
    }

    func composeSplitEmptyPlaceholders() -> EmptySplitService {
        let session = emptySplitSession
        return EmptySplitService(
            placeholders: EmptySplitPlaceholderFactory(
                spaces: spaceStateOwner,
                regularTabs: regularTabLifecycleOwner,
                retirement: splitPlaceholderRetirement,
                structuralTransactions: structuralLookupCoordinator,
                terminalMutations: structuralCollectionMutationOwner
            ),
            insertion: splitInsertion,
            activations: shortcutPresentationActivation,
            session: session,
            replacements: EmptySplitReplacementService(
                replacements: splitPlaceholderReplacements,
                session: session,
                terminalMutations: structuralCollectionMutationOwner
            )
        )
    }

    func composeSplitEmptyCreation() -> EmptySplitCreationWorkflow {
        EmptySplitCreationWorkflow(
            placeholders: splitEmptyPlaceholders,
            focusFloatingBar: { [weak self] window, reason in
                self?.urlBarBundle.floatingBar.presentation.focus(
                    in: window,
                    prefill: "",
                    navigateCurrentTab: true,
                    reason: reason
                )
            }
        )
    }
}
