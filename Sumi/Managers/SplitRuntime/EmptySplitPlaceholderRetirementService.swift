/// Admits exact placeholder retirement against canonical collection,
/// selection, and runtime-attachment state.
@MainActor
final class EmptySplitPlaceholderRetirementService {
    private let regularTabs: RegularTabCollectionOwner
    private let selection: TabSelectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeCleanup: RegularTabClosureRuntimeCleanup

    init(
        regularTabs: RegularTabCollectionOwner,
        selection: TabSelectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService,
        runtimeConnection: TabRuntimePortConnection,
        runtimeCleanup: RegularTabClosureRuntimeCleanup
    ) {
        self.regularTabs = regularTabs
        self.selection = selection
        self.structuralLookup = structuralLookup
        self.persistence = persistence
        self.runtimeConnection = runtimeConnection
        self.runtimeCleanup = runtimeCleanup
    }

    func prepare(
        _ placeholder: Tab
    ) -> EmptySplitPlaceholderRetirementReceipt? {
        EmptySplitPlaceholderRetirementReceipt(
            placeholder: placeholder,
            regularTabs: regularTabs,
            selection: selection,
            structuralLookup: structuralLookup,
            persistence: persistence,
            runtimeConnection: runtimeConnection,
            runtimeCleanup: runtimeCleanup
        )
    }
}
