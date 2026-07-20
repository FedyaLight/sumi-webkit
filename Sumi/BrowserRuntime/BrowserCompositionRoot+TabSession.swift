import Foundation
import SumiDomain
import SumiWebRuntime
import SwiftData

@MainActor
extension BrowserCompositionRoot {
    static func makeKernelWithTabSession(
        modelContext: ModelContext,
        windowRegistry: WindowRegistry,
        moduleRegistry: SumiModuleRegistry,
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling,
        adBlockingModule: SumiAdBlockingModule,
        protectionCoordinator: SumiProtectionCoordinator,
        adblockZapperStore: SumiAdblockZapperStore,
        windowSessionPersistence: WindowSessionPersistenceRuntime,
        profileRetirementStartupPreflight: ProfileRetirementStartupPreflightStatus,
        profileManager: ProfileManager,
        optionalModules: OptionalModuleHost,
        tabStructureEventBus: TabStructureEventBus,
        webViewSessions: WebViewSessionRepository,
        dataServices: BrowserManagerDataServices,
        initialProfile: Profile?,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        downloadManager: DownloadManager,
        downloadTransportFactory: any DownloadWebKitTransportAdapting,
        authenticationManager: AuthenticationManager,
        historyManager: HistoryManager,
        bookmarkManager: SumiBookmarkManager,
        recentlyClosedManager: RecentlyClosedManager,
        lastSessionWindowsStore: LastSessionWindowsStore,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner,
        compositorManager: TabCompositorManager,
        tabSuspensionController: TabSuspensionController,
        workspaceThemeCoordinator: WorkspaceThemeCoordinator,
        findManager: FindManager,
        browserConfiguration: BrowserConfiguration,
        browsingDataCleanupService: SumiBrowsingDataCleanupService,
        nativeNowPlayingController: any SumiNativeNowPlayingRuntimeControlling,
        permissionRuntime: BrowserManagerPermissionRuntime,
        initialTabRuntimePorts: RuntimePortRegistry?,
        loadPersistedState: Bool,
        automaticallyStartPersistedStateLoad: Bool
    ) -> BrowserKernelGraph {
        let tabManager = TabManager(
            context: modelContext,
            webViewSessions: webViewSessions,
            profileReferenceAdmission: profileReferenceAdmission,
            initialRuntimePorts: initialTabRuntimePorts,
            loadPersistedState: loadPersistedState,
            automaticallyStartPersistedStateLoad: automaticallyStartPersistedStateLoad,
            tabStructureEventBus: tabStructureEventBus,
            faviconService: dataServices.faviconService,
            faviconCapabilities: dataServices.faviconCapabilities,
            visitedLinkStore: dataServices.visitedLinkStore
        )
        let state = tabManager.stateStore
        let runtimeConnection = tabManager.runtimePortConnection
        let structuralPersistence = tabManager.structuralPersistence
        let runtimePreparationOwner = TabRuntimePreparationOwner(
            runtimeConnection: runtimeConnection
        )
        let structuralLookupCoordinator = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: state
        )
        let structuralCollectionStore = TabStructuralCollectionStore(
            regularTabs: state.regularTabs,
            folders: state.folders,
            shortcutPins: state.shortcutPins
        )
        let structuralCollectionSnapshots = TabStructuralCollectionSnapshotStore(
            regularTabs: state.regularTabs,
            folders: state.folders,
            shortcutPins: state.shortcutPins
        )
        let structuralMutationPublisher = TabStructuralMutationPublisher(
            persistence: structuralPersistence,
            faviconService: dataServices.faviconService,
            lookup: structuralLookupCoordinator,
            changes: tabManager.objectWillChange,
            regularTabs: state.regularTabs
        )
        let structuralCollectionMutationOwner = TabStructuralCollectionMutationOwner(
                store: structuralCollectionStore,
                snapshots: structuralCollectionSnapshots,
                publisher: structuralMutationPublisher
            )
        let structuralInstallOwner = TabStructuralInstallOwner(
            state: state,
            structuralLookup: structuralLookupCoordinator,
            persistence: structuralPersistence,
            publication: TabStructuralInstallPublication(
                changes: tabManager.objectWillChange,
                faviconService: dataServices.faviconService
            ),
            profileReferenceAdmission: profileReferenceAdmission
        )
        let tabCollectionMembershipOwner = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookupCoordinator.lookupOwner,
            state: state,
            runtimePreparation: runtimePreparationOwner,
            runtimeConnection: runtimeConnection
        )
        let lazyRestoreCoordinator = TabLazyRestoreCoordinator(
            spaces: state.spaces,
            regularTabs: state.regularTabs,
            membership: tabCollectionMembershipOwner
        )
        let spacePinnedOrderTransaction = SpacePinnedOrderTransaction(
            folders: state.folders,
            pins: state.shortcutPins,
            mutations: structuralCollectionMutationOwner
        )
        let spacePinnedStructureOwner = SpacePinnedStructureOwner(
            folders: state.folders,
            pins: state.shortcutPins,
            splitGroups: state.splitGroups,
            orderTransaction: spacePinnedOrderTransaction
        )
        let runtimeTeardown = TabRuntimeTeardownService(
            persistence: structuralPersistence,
            membership: tabCollectionMembershipOwner,
            webViewSessions: webViewSessions
        )
        let liveShortcutTabs = LiveShortcutTabRegistry(
            storage: state.transientTabs,
            structuralLookup: structuralLookupCoordinator
        )
        let liveShortcutTabBatchRetirement = LiveShortcutTabBatchRetirement(
            storage: state.transientTabs,
            structuralLookup: structuralLookupCoordinator
        )
        let splitGroupMutations = SplitGroupMutationService(
            store: state.splitGroups,
            publication: structuralMutationPublisher
        )
        let splitGroupSidebarOrdering =
            SplitGroupSidebarOrderingService(
                store: state.splitGroups,
                folders: state.folders,
                pins: state.shortcutPins
            )
        let spacePinnedVisualOrder = SpacePinnedVisualOrderTransaction(
            ordering: splitGroupSidebarOrdering,
            groupMutations: splitGroupMutations,
            orderTransaction: spacePinnedOrderTransaction
        )
        let splitGroupMembership = SplitGroupMembershipQuery(
            store: state.splitGroups,
            tabs: tabCollectionMembershipOwner,
            pins: state.shortcutPins
        )
        let shortcutPinRuntimeResolutionOwner = ShortcutPinRuntimeResolutionOwner(
                spaces: state.spaces,
                runtimeConnection: runtimeConnection,
                faviconService: dataServices.faviconService
            )
        let shortcutWindowMutationOwner = BrowserWindowShortcutMutationOwner()
        let shortcutPresentationOwner = TabShortcutPresentationOwner(
            transientTabs: state.transientTabs,
            runtimeConnection: runtimeConnection,
            pins: state.shortcutPins,
            dragProxyFactory: ShortcutDragProxyFactory(
                resolution: shortcutPinRuntimeResolutionOwner,
                tabFactory: tabManager.tabFactory,
                runtimePreparation: runtimePreparationOwner
            )
        )

        let profileAssignmentPolicy = ProfileAssignmentPolicy(
            runtimeConnection: runtimeConnection,
            spaces: state.spaces,
            membership: tabCollectionMembershipOwner,
            transientTabs: state.transientTabs
        )
        let pendingTabProfileInheritance = PendingTabProfileInheritance()
        let tabProfileTransitions = TabProfileTransitionService(
            runtimeConnection: runtimeConnection,
            policy: profileAssignmentPolicy,
            pendingInheritance: pendingTabProfileInheritance,
            publication: TabProfileTransitionPublication(
                spaces: state.spaces,
                membership: tabCollectionMembershipOwner,
                persistence: structuralPersistence,
                structuralLookup: structuralLookupCoordinator
            )
        )
        let regularTabPlacementAdmission = RegularTabPlacementAdmission(
            policy: profileAssignmentPolicy,
            references: profileReferenceAdmission,
            profiles: tabProfileTransitions
        )
        let regularTabPlacementTransaction = RegularTabPlacementTransaction(
            stateOwner: state.regularTabs,
            structuralMutations: structuralCollectionMutationOwner,
            structuralLookup: structuralLookupCoordinator,
            admission: regularTabPlacementAdmission
        )
        let regularTabStructuralTransaction = RegularTabStructuralTransaction(
            mutations: structuralCollectionMutationOwner,
            structuralLookup: structuralLookupCoordinator,
            persistence: structuralPersistence
        )
        let regularTabCollectionOwner = RegularTabCollectionOwner(
            stateOwner: state.regularTabs,
            structuralTransaction: regularTabStructuralTransaction,
            shortcutPresentation: shortcutPresentationOwner,
            pins: state.shortcutPins,
            placementTransaction: regularTabPlacementTransaction
        )
        let activeSpaceSelectionUpdater = TabActiveSpaceSelectionUpdater(
            spaces: state.spaces,
            persistence: structuralPersistence
        )
        let activeSelectionOwner = TabActiveSelectionOwner(
            membership: tabCollectionMembershipOwner,
            selection: state.selection,
            runtimeConnection: runtimeConnection,
            persistence: structuralPersistence,
            spaceSelection: activeSpaceSelectionUpdater
        )
        let selectionContextProjection = TabSelectionContextProjection(
            runtimeConnection: runtimeConnection,
            spaces: state.spaces,
            regularTabs: regularTabCollectionOwner,
            shortcutPresentation: shortcutPresentationOwner
        )
        let spaceProfileGraph = SpaceProfileTransitionService.compose(
            spaces: state.spaces,
            pins: state.shortcutPins,
            registry: liveShortcutTabs,
            runtimeConnection: runtimeConnection,
            runtimeTeardown: runtimeTeardown,
            structuralLookup: structuralLookupCoordinator,
            membership: tabCollectionMembershipOwner,
            persistence: structuralPersistence,
            pendingInheritance: pendingTabProfileInheritance,
            changes: tabManager.objectWillChange
        )
        let pendingShortcutPinAdopter = PendingShortcutPinAdopter(
            pins: state.shortcutPins,
            structuralMutations: structuralCollectionMutationOwner,
            profileReferenceAdmission: profileReferenceAdmission
        )
        let profileSelection = ProfileSelectionCoordinator(
            selectionContext: selectionContextProjection,
            selection: state.selection,
            pins: state.shortcutPins,
            runtimeConnection: runtimeConnection,
            persistence: structuralPersistence
        )
        let shortcutReferences = ShortcutProfileReferenceRetirementService.compose(
            pins: state.shortcutPins,
            splitGroups: state.splitGroups,
            pendingPins: pendingShortcutPinAdopter,
            splitMutations: splitGroupMutations,
            structuralMutations: structuralCollectionMutationOwner,
            spacePinnedStructure: spacePinnedStructureOwner,
            runtimeConnection: runtimeConnection,
            profileReferenceAdmission: profileReferenceAdmission
        )
        let profileDeletion = ProfileDeletionMigration.compose(
            policy: profileAssignmentPolicy,
            runtimeConnection: runtimeConnection,
            spaces: state.spaces,
            tabTransitions: tabProfileTransitions,
            spaceTransitions: spaceProfileGraph.service,
            spaceTransitionLifecycle: spaceProfileGraph.lifecycle,
            shortcutReferences: shortcutReferences,
            selection: profileSelection
        )
        let spaceProfileReconciliation = SpaceProfileReconciliationService(
            spaces: state.spaces,
            runtimeConnection: runtimeConnection,
            spaceTransitions: spaceProfileGraph.service,
            transitionLifecycle: spaceProfileGraph.lifecycle
        )
        let spaceLauncherProjection = SpaceLauncherProjectionService(
            regularTabs: state.regularTabs,
            pins: state.shortcutPins,
            folders: state.folders,
            splitOrdering: splitGroupSidebarOrdering,
            transientTabs: state.transientTabs
        )
        let spaceCreation = SpaceCreationTransaction(
            transactions: structuralLookupCoordinator,
            spaces: state.spaces,
            runtimeConnection: runtimeConnection,
            profileReferenceAdmission: profileReferenceAdmission,
            committer: SpaceCreationCommitter(
                structuralMutations: structuralCollectionMutationOwner,
                persistence: structuralPersistence,
                changes: tabManager.objectWillChange
            )
        )
        let spaceCatalog = SpaceCatalogCommands(
            transactions: structuralLookupCoordinator,
            spaces: state.spaces,
            creation: spaceCreation,
            runtimeConnection: runtimeConnection,
            publication: SpaceCatalogMutationPublication(
                persistence: structuralPersistence,
                changes: tabManager.objectWillChange
            )
        )
        let spaceActivation = SpaceActivationService(
            state: state,
            projection: spaceLauncherProjection,
            persistence: structuralPersistence,
            profileAdmission: SpaceActivationProfileAdmission(
                runtimeConnection: runtimeConnection,
                profileTransitions: spaceProfileGraph.service
            ),
            shortcutPresentation: shortcutPresentationOwner
        )
        let tabCreationPlacement = TabCreationPlacementService(
            spaces: state.spaces,
            catalog: spaceCatalog,
            profilePolicy: profileAssignmentPolicy,
            profileTransitions: spaceProfileGraph.service,
            membership: tabCollectionMembershipOwner
        )
        let spaceContentRetirement = SpaceContentRetirementService(
            state: state,
            structuralMutations: structuralCollectionMutationOwner,
            splitGroups: SpaceSplitGroupRetirementService(
                store: state.splitGroups,
                mutations: splitGroupMutations
            ),
            liveShortcutRetirement: liveShortcutTabBatchRetirement,
            runtimeTeardown: runtimeTeardown
        )
        let deletedSpaceWindowStates = DeletedSpaceWindowStateReconciler(
            runtimeConnection: runtimeConnection
        )
        let spaceRemoval = SpaceRemovalService(
            transactions: structuralLookupCoordinator,
            contentRetirement: spaceContentRetirement,
            windowStates: deletedSpaceWindowStates,
            catalog: SpaceRemovalCatalogCommitter(
                state: state,
                persistence: structuralPersistence,
                changes: tabManager.objectWillChange
            )
        )
        let spaceClearing = SpaceClearingService(
            transactions: structuralLookupCoordinator,
            contentRetirement: spaceContentRetirement,
            windowStates: deletedSpaceWindowStates,
            persistence: structuralPersistence
        )
        let shortcutTabWindowQuery = ShortcutTabWindowQuery(
            runtimeConnection: runtimeConnection
        )
        let regularTabResidencePublication = RegularTabResidencePublication(
            membership: tabCollectionMembershipOwner,
            regularTabs: regularTabCollectionOwner,
            persistence: structuralPersistence
        )
        let regularTabVisibleRuntimeEffects = RegularTabVisibleRuntimeEffects(
            selection: state.selection,
            windows: shortcutTabWindowQuery,
            runtimeConnection: runtimeConnection
        )
        let regularTabPublication = RegularTabPublicationTransaction(
            structuralLookup: structuralLookupCoordinator,
            residence: regularTabResidencePublication,
            visibleRuntime: regularTabVisibleRuntimeEffects
        )
        let glanceTabAdoptionCommitter = GlanceTabAdoptionCommitter(
            creationPlacement: tabCreationPlacement,
            profileAdmissions: profileReferenceAdmission,
            regularTabs: regularTabCollectionOwner,
            runtimeConnection: runtimeConnection,
            publication: regularTabPublication
        )
        let glanceTabAdoption = GlanceTabAdoptionTransaction(
            structuralLookup: structuralLookupCoordinator,
            membership: tabCollectionMembershipOwner,
            regularTabs: regularTabCollectionOwner,
            committer: glanceTabAdoptionCommitter
        )
        let regularTabCreationCandidates = RegularTabCreationCandidateFactory(
            runtimeConnection: runtimeConnection,
            tabFactory: tabManager.tabFactory,
            regularTabs: regularTabCollectionOwner
        )
        let regularTabCreationTransaction = RegularTabCreationTransaction(
            creationPlacement: tabCreationPlacement,
            profileAdmissions: profileReferenceAdmission,
            candidates: regularTabCreationCandidates,
            publication: regularTabPublication
        )
        let regularTabCreation = RegularTabCreationService(
            structuralLookup: structuralLookupCoordinator,
            creation: regularTabCreationTransaction,
            candidates: regularTabCreationCandidates,
            selection: activeSelectionOwner
        )
        let regularTabLifecycleOwner = TabRegularLifecycleOwner(
            publication: regularTabPublication,
            glanceAdoption: glanceTabAdoption,
            creation: regularTabCreation
        )
        let transientExtensionTabResidence = TransientExtensionTabResidenceQuery(
            membership: tabCollectionMembershipOwner
        )
        let transientExtensionTabCreation =
            TransientExtensionTabCreationTransaction(
            urlResolver: TransientExtensionTabURLResolver(
                runtimeConnection: runtimeConnection
            ),
            creationPlacement: tabCreationPlacement,
            profileAdmissions: profileReferenceAdmission,
            installer: TransientExtensionTabInstaller(
                membership: tabCollectionMembershipOwner,
                regularTabs: regularTabCollectionOwner,
                tabFactory: tabManager.tabFactory,
                residence: transientExtensionTabResidence
            )
        )
        let transientExtensionTabRetirement =
            TransientExtensionTabRetirementTransaction(
                runtimeConnection: runtimeConnection,
                membership: tabCollectionMembershipOwner
            )
        let extensionRequestedTabDiscard = ExtensionRequestedTabDiscardService(
            transactions: structuralLookupCoordinator,
            residenceRemoval: ExtensionRequestedTabResidenceRemovalTransaction(
                membership: tabCollectionMembershipOwner,
                transientTabs: transientExtensionTabRetirement,
                regularTabs: regularTabCollectionOwner,
                spaces: state.spaces,
                persistence: structuralPersistence
            ),
            runtimeSettlement: ExtensionRequestedTabRuntimeSettlementTransaction(
                runtimeConnection: runtimeConnection,
                membership: tabCollectionMembershipOwner,
                persistence: structuralPersistence
            ),
            selectionRestoration: ExtensionRequestedTabSelectionRestoration(
                selection: state.selection,
                membership: tabCollectionMembershipOwner
            )
        )
        let auxiliaryMiniWindowTabs = AuxiliaryMiniWindowTabLifecycleTransaction(
            runtimeConnection: runtimeConnection,
            membership: tabCollectionMembershipOwner,
            profileAdmissions: profileReferenceAdmission,
            tabFactory: tabManager.tabFactory
        )
        let transientExtensionPromotion = TransientExtensionTabPromotionTransaction(
            spaces: state.spaces,
            membership: tabCollectionMembershipOwner,
            regularTabs: regularTabCollectionOwner,
            persistence: structuralPersistence,
            selection: activeSelectionOwner
        )
        let ephemeralLifecycleOwner = TabEphemeralLifecycleOwner(
            runtimePreparation: runtimePreparationOwner,
            tabFactory: tabManager.tabFactory
        )
        let shortcutLiveTabRetirement = ShortcutLiveTabRetirementService(
            registry: liveShortcutTabs,
            structuralLookup: structuralLookupCoordinator,
            runtimeConnection: runtimeConnection,
            runtimeTeardown: runtimeTeardown,
            windowMutations: shortcutWindowMutationOwner,
            splitGroups: state.splitGroups,
            splitMutations: splitGroupMutations
        )
        let tabClosureCandidateRetirement = TabClosureCandidateRetirement(
            shortcutRetirement: shortcutLiveTabRetirement,
            persistence: structuralPersistence,
            transientExtensionTabs: transientExtensionTabRetirement,
            auxiliaryMiniWindowTabs: auxiliaryMiniWindowTabs
        )
        let tabClosureService = TabClosureService(
            transactions: structuralLookupCoordinator,
            candidateRetirement: tabClosureCandidateRetirement,
            regularCommit: RegularTabClosureCommitTransaction(
                regularTabs: regularTabCollectionOwner,
                spaces: state.spaces,
                runtimeCleanup: RegularTabClosureRuntimeCleanup(
                    membership: tabCollectionMembershipOwner
                ),
                persistence: structuralPersistence,
                runtimePorts: runtimeConnection
            ),
            selectionRepair: RegularTabClosureSelectionRepair(
                selection: state.selection,
                spaces: state.spaces,
                regularTabs: regularTabCollectionOwner,
                shortcutPresentation: shortcutPresentationOwner
            ),
            targets: RegularTabClosureTargetQuery(
                regularTabs: regularTabCollectionOwner,
                selection: state.selection
            )
        )
        let folderOpenState = TabFolderOpenStateService(
            folders: state.folders,
            structuralLookup: structuralLookupCoordinator,
            persistence: structuralPersistence
        )
        let shortcutPinStoreOwner = ShortcutPinStoreOwner(
            placements: ShortcutPinPlacementResolver(
                destinationValidator: ShortcutPinDestinationValidator(
                    spaces: state.spaces,
                    folders: state.folders
                ),
                pins: state.shortcutPins,
                spacePinnedStructure: spacePinnedStructureOwner
            ),
            mutations: ShortcutPinCatalogMutationTransaction(
                pins: state.shortcutPins,
                structuralMutations: structuralCollectionMutationOwner,
                spacePinnedStructure: spacePinnedStructureOwner,
                spacePinnedVisualOrder: spacePinnedVisualOrder,
                profileAdmissions: profileReferenceAdmission
            ),
            folderOpenState: folderOpenState
        )
        let liveShortcutPresentationRefreshes = LiveShortcutPresentationRefreshService(
                registry: liveShortcutTabs,
                resolution: shortcutPinRuntimeResolutionOwner
            )
        let shortcutBindingTargets = ShortcutTabBindingTargetMutationService(
            resolution: shortcutPinRuntimeResolutionOwner,
            profiles: tabProfileTransitions
        )
        let shortcutTabBindings = ShortcutTabBindingSynchronizer(
            presentationRefreshes: liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: liveShortcutTabs,
                targets: shortcutBindingTargets,
                runtimeConnection: runtimeConnection,
                windowMutations: shortcutWindowMutationOwner,
                structuralLookup: structuralLookupCoordinator
            ),
            targets: shortcutBindingTargets
        )
        let splitGroupLauncherPlacement =
            ShortcutSplitLauncherPlacementService(
                pins: state.shortcutPins,
                moves: ShortcutSplitLauncherMoveTransaction(
                    batches: ShortcutSplitLauncherMoveBatchStaging(
                        catalog: ShortcutSplitLauncherCatalogTransaction(
                            pinStore: shortcutPinStoreOwner,
                            pins: state.shortcutPins
                        ),
                        bindingStaging: ShortcutSplitLauncherBindingStaging(
                            refreshes: liveShortcutPresentationRefreshes,
                            resolution: shortcutPinRuntimeResolutionOwner,
                            batches: ShortcutTabBindingBatchFactory(
                                runtimeConnection: runtimeConnection,
                                windowMutations: shortcutWindowMutationOwner,
                                profiles: tabProfileTransitions,
                                persistence:
                                    ShortcutSplitLauncherWindowPersistence(
                                        structuralLookup:
                                            structuralLookupCoordinator
                                    ),
                                structuralLookup: structuralLookupCoordinator
                            )
                        ),
                        residenceMutations: liveShortcutTabs.staging,
                        structuralMutations: structuralCollectionMutationOwner,
                        structuralLookup: structuralLookupCoordinator
                    ),
                    windowMutations: shortcutWindowMutationOwner,
                    folderOpenState: folderOpenState
                )
            )
        let shortcutFreshTabs = ShortcutFreshTabFactory(
            tabFactory: tabManager.tabFactory,
            bindings: shortcutTabBindings
        )
        let shortcutTabMaterializer = ShortcutTabMaterializer(
            resolution: shortcutPinRuntimeResolutionOwner,
            committer: ShortcutTabMaterializationCommitter(
                registry: liveShortcutTabs,
                bindings: shortcutTabBindings,
                freshTabs: shortcutFreshTabs,
                membership: tabCollectionMembershipOwner,
                structuralLookup: structuralLookupCoordinator
            )
        )
        let shortcutPresentationActivation =
            ShortcutPresentationActivationService(
                planner: ShortcutPresentationActivationPlanner(
                    pins: state.shortcutPins,
                    registry: liveShortcutTabs,
                    resolution: shortcutPinRuntimeResolutionOwner,
                    freshTabs: shortcutFreshTabs,
                    membership: tabCollectionMembershipOwner
                ),
                committer: ShortcutPresentationActivationCommitter(
                    registry: liveShortcutTabs,
                    membership: tabCollectionMembershipOwner
                ),
                structuralLookup: structuralLookupCoordinator
            )
        let shortcutContainerRemovalOwner = ShortcutContainerRemovalOwner(
            pins: state.shortcutPins,
            structuralMutations: structuralCollectionMutationOwner,
            regularTabs: regularTabCollectionOwner,
            spaces: state.spaces
        )
        let regularTabShortcutTransaction =
            RegularTabShortcutCommitTransaction.compose(
                pinStore: shortcutPinStoreOwner,
                pins: state.shortcutPins,
                splitMutations: splitGroupMutations,
                structuralMutations: structuralCollectionMutationOwner,
                persistence: structuralPersistence,
                folders: folderOpenState,
                registry: liveShortcutTabs,
                membership: tabCollectionMembershipOwner,
                resolution: shortcutPinRuntimeResolutionOwner,
                tabFactory: tabManager.tabFactory,
                bindings: shortcutTabBindings,
                runtimeConnection: runtimeConnection,
                windowMutations: shortcutWindowMutationOwner,
                profiles: tabProfileTransitions,
                structuralLookup: structuralLookupCoordinator,
                windows: shortcutTabWindowQuery,
                containerRemoval: shortcutContainerRemovalOwner,
                selection: state.selection,
                runtimeTeardown: runtimeTeardown,
                regularTabs: regularTabCollectionOwner
            )
        let regularTabShortcutConversion =
            RegularTabShortcutConversionService.compose(
                windows: shortcutTabWindowQuery,
                regularTabs: regularTabCollectionOwner,
                splitGroups: state.splitGroups,
                structuralLookup: structuralLookupCoordinator,
                runtimeConnection: runtimeConnection,
                resolution: shortcutPinRuntimeResolutionOwner,
                transaction: regularTabShortcutTransaction
            )
        let shortcutTabPromotion = ShortcutTabPromotionService.compose(
            registry: liveShortcutTabs,
            spaces: state.spaces,
            splitGroups: state.splitGroups,
            tabFactory: tabManager.tabFactory,
            regularTabs: regularTabCollectionOwner,
            runtimeConnection: runtimeConnection,
            retirement: shortcutLiveTabRetirement,
            membership: tabCollectionMembershipOwner,
            structuralLookup: structuralLookupCoordinator
        )
        let shortcutPinToRegularTab = ShortcutPinToRegularTabService.compose(
            promotion: shortcutTabPromotion,
            splitGroups: state.splitGroups,
            splitMutations: splitGroupMutations,
            pinStore: shortcutPinStoreOwner,
            pins: state.shortcutPins,
            persistence: structuralPersistence,
            structuralLookup: structuralLookupCoordinator
        )
        let shortcutPinMetadataMutations = ShortcutPinMetadataMutationService(
            pins: state.shortcutPins,
            bindings: shortcutTabBindings,
            profileAdmissions: profileReferenceAdmission,
            persistence: structuralPersistence,
            commitTransaction: ShortcutPinMetadataCommitTransaction(
                pins: state.shortcutPins,
                structuralMutations: structuralCollectionMutationOwner,
                spacePinnedStructure: spacePinnedStructureOwner,
                bindings: shortcutTabBindings
            )
        )
        let essentialsShortcutPlacementOwner = EssentialsShortcutPlacementOwner(
            spaces: state.spaces,
            runtimeConnection: runtimeConnection,
            pins: state.shortcutPins,
            splitGroups: state.splitGroups
        )
        let essentialsVisualOrder = EssentialsVisualOrderTransaction(
            ordering: splitGroupSidebarOrdering,
            groupMutations: splitGroupMutations,
            pins: state.shortcutPins,
            structuralMutations: structuralCollectionMutationOwner
        )
        let shortcutPinPlacementCommands =
            ShortcutPinCommandComposition.makePlacement(
                pins: state.shortcutPins,
                structuralLookup: structuralLookupCoordinator,
                structuralMutations: structuralCollectionMutationOwner,
                runtimeConnection: runtimeConnection,
                store: shortcutPinStoreOwner,
                spacePinnedStructure: spacePinnedStructureOwner,
                spacePinnedVisualOrder: spacePinnedVisualOrder,
                bindings: shortcutTabBindings,
                essentialsVisualOrder: essentialsVisualOrder
            )
        let regularTabShortcutConversionCommand =
            RegularTabShortcutConversionCommand(
                structuralLookup: structuralLookupCoordinator,
                runtimeConnection: runtimeConnection,
                conversion: regularTabShortcutConversion
            )
        let splitGroupShortcutMoves = SplitGroupShortcutMoveService(
            conversion: regularTabShortcutConversion,
            groups: splitGroupMutations,
            structuralLookup: structuralLookupCoordinator,
            runtimeConnection: runtimeConnection,
            windowMutations: shortcutWindowMutationOwner
        )
        let splitGroupShortcutMemberRelocation =
            SplitGroupShortcutMemberRelocation(
                ordering: splitGroupSidebarOrdering,
                mutations: splitGroupMutations,
                launcherPlacement: splitGroupLauncherPlacement
            )
        let splitGroupContainerConversion = SplitGroupContainerConversion(
            ordering: splitGroupSidebarOrdering,
            mutations: splitGroupMutations,
            folders: state.folders,
            regularTabs: regularTabCollectionOwner,
            spacePinnedVisualOrder: spacePinnedVisualOrder,
            launcherPlacement: splitGroupLauncherPlacement,
            shortcutMoves: splitGroupShortcutMoves,
            shortcutToRegular: shortcutPinToRegularTab,
            essentialsVisualOrder: essentialsVisualOrder
        )
        let regularTabEssentialPinning = RegularTabEssentialPinningService(
            structuralLookup: structuralLookupCoordinator,
            placement: essentialsShortcutPlacementOwner,
            pins: state.shortcutPins,
            conversion: regularTabShortcutConversion
        )
        let shortcutPinEssentialCopy = ShortcutPinEssentialCopyTransaction(
            structuralLookup: structuralLookupCoordinator,
            preparer: ShortcutPinEssentialCopyPreparer(
                placement: essentialsShortcutPlacementOwner,
                pins: state.shortcutPins,
                resolution: shortcutPinRuntimeResolutionOwner
            ),
            store: shortcutPinStoreOwner,
            structuralMutations: structuralCollectionMutationOwner
        )
        let shortcutPinSpacePinning = ShortcutPinSpacePinningTransaction(
            structuralLookup: structuralLookupCoordinator,
            spaces: state.spaces,
            pins: state.shortcutPins,
            rebinder: EssentialShortcutSpaceRebinder(
                resolution: shortcutPinRuntimeResolutionOwner,
                bindings: shortcutTabBindings,
                store: shortcutPinStoreOwner,
                structuralMutations: structuralCollectionMutationOwner
            ),
            conversion: regularTabShortcutConversion
        )
        let shortcutPinRetirement = ShortcutPinRetirementTransaction(
            structuralLookup: structuralLookupCoordinator,
            pins: state.shortcutPins,
            committer: ShortcutPinRetirementCommitter(
                retirement: shortcutLiveTabRetirement,
                runtimeConnection: runtimeConnection,
                store: shortcutPinStoreOwner,
                structuralMutations: structuralCollectionMutationOwner
            )
        )
        let shortcutPinLivePages = ShortcutPinLivePageMutationService(
            structuralLookup: structuralLookupCoordinator,
            pins: state.shortcutPins,
            presentation: shortcutPresentationOwner,
            preservation: ShortcutLivePagePreservationTransaction(
                tabFactory: tabManager.tabFactory,
                membership: tabCollectionMembershipOwner,
                regularTabs: regularTabCollectionOwner,
                structuralMutations: structuralCollectionMutationOwner
            )
        )
        let sidebarPinCommands = SidebarPinCommands(
            runtime: runtimeConnection,
            windows: SidebarWindowIdentityQuery(registry: windowRegistry),
            pins: state.shortcutPins,
            folders: state.folders,
            structure: spacePinnedStructureOwner,
            placement: shortcutPinPlacementCommands,
            essentialCopy: shortcutPinEssentialCopy,
            essentialPinning: regularTabEssentialPinning,
            retirement: shortcutPinRetirement,
            livePages: shortcutPinLivePages,
            metadata: shortcutPinMetadataMutations
        )
        let extensionTabCommands = BrowserExtensionTabCommands(
            regularTabs: regularTabLifecycleOwner,
            transientTabs: BrowserTransientExtensionTabCommands(
                creation: transientExtensionTabCreation,
                residence: transientExtensionTabResidence,
                promotion: transientExtensionPromotion,
                spaces: state.spaces
            ),
            pinning: sidebarPinCommands,
            requestedDiscard: extensionRequestedTabDiscard
        )
        let shortcutDragOperationOwner = ShortcutDragOperationOwner(
            placement: shortcutPinPlacementCommands,
            pinToRegular: shortcutPinToRegularTab,
            folders: state.folders,
            essentialsPlacement: essentialsShortcutPlacementOwner
        )
        let folderHierarchyMutations = TabFolderHierarchyMutationService(
            folders: state.folders,
            pins: state.shortcutPins,
            structuralMutations: structuralCollectionMutationOwner,
            spacePinnedStructure: spacePinnedStructureOwner,
            shortcutBindings: shortcutTabBindings
        )
        let folderContentMutations = TabFolderContentMutationTransaction(
            structuralLookup: structuralLookupCoordinator,
            spaces: state.spaces,
            folders: state.folders,
            hierarchy: folderHierarchyMutations,
            persistence: structuralPersistence
        )
        let folderPlacementAdmission = TabFolderPlacementAdmission(
            folders: state.folders,
            hierarchy: folderHierarchyMutations,
            runtimeConnection: runtimeConnection
        )
        let folderPlacementCommit = TabFolderPlacementCommitTransaction(
            hierarchy: folderHierarchyMutations,
            spacePinnedStructure: spacePinnedStructureOwner,
            spacePinnedVisualOrder: spacePinnedVisualOrder,
            folderOpenState: folderOpenState,
            structuralMutations: structuralCollectionMutationOwner
        )
        let folderPlacement = TabFolderPlacementTransaction(
            structuralLookup: structuralLookupCoordinator,
            admission: folderPlacementAdmission,
            commitTransaction: folderPlacementCommit
        )
        let folderDeletionPreparation = TabFolderDeletionPreparationService(
            folders: state.folders,
            pins: state.shortcutPins,
            hierarchy: folderHierarchyMutations,
            membership: tabCollectionMembershipOwner
        )
        let folderDeletionCommit = TabFolderDeletionCommitTransaction(
            hierarchy: folderHierarchyMutations,
            shortcutRetirement: shortcutLiveTabRetirement,
            tabClosure: tabClosureService,
            runtimeConnection: runtimeConnection,
            persistence: structuralPersistence
        )
        let folderUngroupPreparation = TabFolderUngroupPreparationService(
            folders: state.folders,
            hierarchy: folderHierarchyMutations,
            membership: tabCollectionMembershipOwner
        )
        let folderUngroupCommit = TabFolderUngroupCommitTransaction(
            hierarchy: folderHierarchyMutations,
            runtimeConnection: runtimeConnection,
            persistence: structuralPersistence
        )
        let folderRetirement = TabFolderRetirementTransaction(
            structuralLookup: structuralLookupCoordinator,
            deletionPreparation: folderDeletionPreparation,
            deletionCommit: folderDeletionCommit,
            ungroupPreparation: folderUngroupPreparation,
            ungroupCommit: folderUngroupCommit
        )
        let folderTabPlacement = TabFolderTabPlacementTransaction(
            structuralLookup: structuralLookupCoordinator,
            targets: TabFolderShortcutPlacementTargetQuery(
                folders: state.folders,
                pins: state.shortcutPins,
                runtimeConnection: runtimeConnection
            ),
            folderOpenState: folderOpenState,
            shortcutPlacement: shortcutPinPlacementCommands,
            shortcutConversion: regularTabShortcutConversionCommand
        )
        let sidebarRegularTabPlacement = SidebarRegularTabPlacementTransaction(
            regularTabs: regularTabCollectionOwner,
            shortcutRemoval: shortcutContainerRemovalOwner,
            persistence: structuralPersistence
        )
        let regularTabDragService = SidebarRegularTabDragService(
            shortcuts: SidebarRegularTabShortcutTransaction(
                placement: shortcutPinPlacementCommands,
                conversion: regularTabShortcutConversionCommand,
                essentialsPlacement: essentialsShortcutPlacementOwner,
                folders: state.folders,
                pins: state.shortcutPins
            ),
            regularTabs: sidebarRegularTabPlacement,
            splitRetirement: SidebarDraggedTabSplitRetirementTransaction(
                runtimeConnection: runtimeConnection
            )
        )
        let sidebarDragPayloadResolver = SidebarDragPayloadResolver(
            membership: tabCollectionMembershipOwner,
            pins: state.shortcutPins,
            presentation: shortcutPresentationOwner,
            folders: state.folders,
            splits: state.splitGroups
        )
        let sidebarDragRouter = SidebarDragOperationRouter(
            resolution: sidebarDragPayloadResolver,
            dragOperations: SidebarDragOperationTransaction(
                structuralLookup: structuralLookupCoordinator,
                resolution: sidebarDragPayloadResolver,
                validation: SidebarDragContextValidationService(
                    spaces: state.spaces,
                    folders: state.folders,
                    pins: state.shortcutPins
                ),
                orderProjection: SidebarDropOrderProjection(
                    regularTabs: regularTabCollectionOwner,
                    splitOrdering: splitGroupSidebarOrdering
                ),
                mutation: SidebarCanonicalDragMutation(
                    folderPlacement: folderPlacement,
                    shortcuts: shortcutDragOperationOwner,
                    regularTabs: regularTabDragService,
                    splits: splitGroupContainerConversion,
                    payloads: sidebarDragPayloadResolver
                )
            ),
            explicitMoves: SidebarExplicitTabMoveTransaction(
                structuralLookup: structuralLookupCoordinator,
                resolution: sidebarDragPayloadResolver,
                regularTabs: sidebarRegularTabPlacement
            )
        )
        let sidebarFolderCommands = SidebarFolderCommands(
            runtime: runtimeConnection,
            folders: state.folders,
            structure: spacePinnedStructureOwner,
            content: folderContentMutations,
            retirement: folderRetirement,
            openState: folderOpenState
        )
        let sidebarRegularTabLifecycleCommands =
            SidebarRegularTabLifecycleCommands(
                closure: tabClosureService
            )
        let sidebarRegularTabShortcutCommands =
            SidebarRegularTabShortcutCommands(
            essentialPinning: regularTabEssentialPinning,
                spacePinning: shortcutPinSpacePinning
            )
        let sidebarRegularTabPlacementCommands =
            SidebarRegularTabPlacementCommands(
            moves: sidebarDragRouter,
            folderTabPlacement: folderTabPlacement,
            profiles: tabProfileTransitions
        )
        let shortcutExecutionProfileAssignments = ShortcutExecutionProfileAssignmentService(
                pins: state.shortcutPins,
                mutations: shortcutPinMetadataMutations,
                policy: profileAssignmentPolicy
            )
        let runtimeStore = DefaultTabRuntimeStore(
            state: state,
            membership: tabCollectionMembershipOwner,
            regularTabs: regularTabCollectionOwner,
            presentation: shortcutPresentationOwner
        )
        let storeRestore = BrowserTabStoreRestoreFactory.make(
            modelContext: modelContext,
            blockedProfileIDs: profileReferenceAdmission.blockedProfileIDs,
            runtimeConnection: runtimeConnection,
            loadLifecycle: tabManager.startupRestoreLifecycle,
            structuralStore: tabManager.structuralSnapshotStore,
            tabFactory: tabManager.tabFactory,
            structuralLookup: structuralLookupCoordinator,
            structuralInstaller: structuralInstallOwner,
            runtimePreparation: runtimePreparationOwner,
            lazyRestore: lazyRestoreCoordinator,
            persistence: structuralPersistence
        )
        let startupStateReset = BrowserTabStartupStateResetFactory.make(
            state: state,
            structuralLookup: structuralLookupCoordinator,
            liveShortcutTabs: liveShortcutTabs,
            runtimeConnection: runtimeConnection,
            runtimeTeardown: runtimeTeardown,
            splitGroupMutations: splitGroupMutations,
            structuralMutations: structuralCollectionMutationOwner,
            persistence: structuralPersistence,
            lazyRestore: lazyRestoreCoordinator,
            shortcutRetirement: liveShortcutTabBatchRetirement
        )
        let lastSessionMergeMaterializer = BrowserLastSessionMergeFactory.make(
            state: state,
            profileAdmissions: profileReferenceAdmission,
            structuralLookup: structuralLookupCoordinator,
            structuralMutations: structuralCollectionMutationOwner,
            spacePinnedStructure: spacePinnedStructureOwner,
            membership: tabCollectionMembershipOwner,
            tabFactory: tabManager.tabFactory,
            persistence: structuralPersistence,
            lazyRestore: lazyRestoreCoordinator,
            changes: tabManager.objectWillChange
        )
        let tabRuntimeLifecycle = BrowserTabRuntimeLifecycleFactory.make(
            state: state,
            runtimeConnection: runtimeConnection,
            startupRestorePolicy: tabManager.startupRestorePolicy,
            startupRestoreLifecycle: tabManager.startupRestoreLifecycle,
            membership: tabCollectionMembershipOwner,
            runtimePreparation: runtimePreparationOwner,
            storeRestore: storeRestore,
            spaceProfiles: spaceProfileReconciliation,
            spaceAvailability: spaceProfileGraph.availability,
            pendingPins: pendingShortcutPinAdopter,
            liveShortcutTabs: liveShortcutTabs
        )
        let tabResidenceAuthority = BrowserTabResidenceAuthorityFactory.make(
            regularTabs: regularTabCollectionOwner,
            liveShortcuts: liveShortcutTabs,
            structuralLookup: structuralLookupCoordinator,
            persistence: structuralPersistence
        )
        let sidebarSpaceLifecycle = BrowserSidebarSpaceLifecycleFactory.make(
            runtime: runtimeConnection,
            spaces: state.spaces,
            pins: state.shortcutPins,
            folders: state.folders,
            splitGroups: state.splitGroups,
            splitOrdering: splitGroupSidebarOrdering,
            regularTabs: regularTabCollectionOwner,
            catalog: spaceCatalog,
            removal: spaceRemoval,
            clearing: spaceClearing
        )

        return BrowserKernelGraph(
            webViewSessions: webViewSessions,
            windowRegistry: windowRegistry,
            modelContext: modelContext,
            moduleRegistry: moduleRegistry,
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            windowSessionPersistence: windowSessionPersistence,
            profileRetirementStartupPreflight:
                profileRetirementStartupPreflight,
            profileManager: profileManager,
            currentProfile: initialProfile,
            optionalModules: optionalModules,
            runtimePortConnection: runtimeConnection,
            tabStateStore: state,
            spaceStateOwner: state.spaces,
            splitGroupStore: state.splitGroups,
            folderCollectionStateOwner: state.folders,
            shortcutPinCollectionStateOwner: state.shortcutPins,
            tabStructureEventBus: tabManager.tabStructureEventBus,
            startupRestoreLifecycle: tabManager.startupRestoreLifecycle,
            structuralPersistence: structuralPersistence,
            profileRuntimeState: tabManager.profileRuntimeState,
            tabFactory: tabManager.tabFactory,
            folderOpenState: folderOpenState,
            regularTabCollectionOwner: regularTabCollectionOwner,
            regularTabLifecycleOwner: regularTabLifecycleOwner,
            tabClosureService: tabClosureService,
            activeSelectionOwner: activeSelectionOwner,
            lazyRestoreCoordinator: lazyRestoreCoordinator,
            spacePinnedStructureOwner: spacePinnedStructureOwner,
            tabProfileTransitions: tabProfileTransitions,
            spaceProfileTransitions: spaceProfileGraph.service,
            profileSelection: profileSelection,
            profileDeletion: profileDeletion,
            shortcutExecutionProfileAssignments:
                shortcutExecutionProfileAssignments,
            sidebarDragRouter: sidebarDragRouter,
            essentialsShortcutPlacementOwner: essentialsShortcutPlacementOwner,
            shortcutPinStoreOwner: shortcutPinStoreOwner,
            shortcutPinRuntimeResolutionOwner:
                shortcutPinRuntimeResolutionOwner,
            shortcutWindowMutationOwner: shortcutWindowMutationOwner,
            shortcutPresentationOwner: shortcutPresentationOwner,
            structuralCollectionMutationOwner:
                structuralCollectionMutationOwner,
            structuralInstallOwner: structuralInstallOwner,
            tabCollectionMembershipOwner: tabCollectionMembershipOwner,
            extensionTabCommands: extensionTabCommands,
            auxiliaryMiniWindowTabs: auxiliaryMiniWindowTabs,
            ephemeralLifecycleOwner: ephemeralLifecycleOwner,
            structuralLookupCoordinator: structuralLookupCoordinator,
            sidebarSpaceLifecycle: sidebarSpaceLifecycle,
            spaceActivation: spaceActivation,
            liveShortcutTabs: liveShortcutTabs,
            liveShortcutPresentationRefreshes:
                liveShortcutPresentationRefreshes,
            shortcutTabMaterializer: shortcutTabMaterializer,
            shortcutPresentationActivation: shortcutPresentationActivation,
            splitGroupMutations: splitGroupMutations,
            splitGroupSidebarOrdering: splitGroupSidebarOrdering,
            splitGroupContainerConversion: splitGroupContainerConversion,
            splitGroupShortcutMemberRelocation:
                splitGroupShortcutMemberRelocation,
            splitGroupMembership: splitGroupMembership,
            regularTabShortcutConversion: regularTabShortcutConversion,
            shortcutLiveTabRetirement: shortcutLiveTabRetirement,
            sidebarPinCommands: sidebarPinCommands,
            sidebarFolderCommands: sidebarFolderCommands,
            sidebarRegularTabLifecycleCommands:
                sidebarRegularTabLifecycleCommands,
            sidebarRegularTabShortcutCommands:
                sidebarRegularTabShortcutCommands,
            sidebarRegularTabPlacementCommands:
                sidebarRegularTabPlacementCommands,
            runtimeStore: runtimeStore,
            startupStateReset: startupStateReset,
            lastSessionMergeMaterializer: lastSessionMergeMaterializer,
            tabRuntimeLifecycle: tabRuntimeLifecycle,
            tabResidenceAuthority: tabResidenceAuthority,
            downloadManager: downloadManager,
            downloadTransportFactory: downloadTransportFactory,
            authenticationManager: authenticationManager,
            historyManager: historyManager,
            bookmarkManager: bookmarkManager,
            recentlyClosedManager: recentlyClosedManager,
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupSessionRestoreOwner: startupSessionRestoreOwner,
            compositorManager: compositorManager,
            tabSuspensionController: tabSuspensionController,
            workspaceThemeCoordinator: workspaceThemeCoordinator,
            findManager: findManager,
            browserConfiguration: browserConfiguration,
            dataServices: dataServices,
            browsingDataCleanupService: browsingDataCleanupService,
            nativeNowPlayingController: nativeNowPlayingController,
            permissionRuntime: permissionRuntime
        )
    }
}
