import Foundation
import SumiWebRuntime

@MainActor
struct BrowserTabStructuralGraph {
    let runtimePreparation: TabRuntimePreparationOwner
    let lookup: TabStructuralLookupCoordinator
    let mutationPublisher: TabStructuralMutationPublisher
    let mutations: TabStructuralCollectionMutationOwner
    let installer: TabStructuralInstallOwner
    let membership: TabCollectionMembershipOwner
    let spacePinnedOrder: SpacePinnedOrderTransaction
    let spacePinnedStructure: SpacePinnedStructureOwner
    let runtimeTeardown: TabRuntimeTeardownService

    static func make(
        tabManager: TabManager,
        webViewSessions: WebViewSessionRepository,
        dataServices: BrowserManagerDataServices,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) -> Self {
        let state = tabManager.stateStore
        let runtimeConnection = tabManager.runtimePortConnection
        let persistence = tabManager.structuralPersistence
        let runtimePreparation = TabRuntimePreparationOwner(
            runtimeConnection: runtimeConnection
        )
        let lookup = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: state
        )
        let collectionStore = TabStructuralCollectionStore(
            regularTabs: state.regularTabs,
            folders: state.folders,
            shortcutPins: state.shortcutPins
        )
        let collectionSnapshots = TabStructuralCollectionSnapshotStore(
            regularTabs: state.regularTabs,
            folders: state.folders,
            shortcutPins: state.shortcutPins
        )
        let mutationPublisher = TabStructuralMutationPublisher(
            persistence: persistence,
            faviconService: dataServices.faviconService,
            lookup: lookup,
            changes: tabManager.objectWillChange,
            regularTabs: state.regularTabs
        )
        let mutations = TabStructuralCollectionMutationOwner(
            store: collectionStore,
            snapshots: collectionSnapshots,
            publisher: mutationPublisher
        )
        let installer = TabStructuralInstallOwner(
            state: state,
            structuralLookup: lookup,
            persistence: persistence,
            publication: TabStructuralInstallPublication(
                changes: tabManager.objectWillChange,
                faviconService: dataServices.faviconService
            ),
            profileReferenceAdmission: profileReferenceAdmission
        )
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: lookup.lookupOwner,
            state: state,
            runtimePreparation: runtimePreparation,
            runtimeConnection: runtimeConnection
        )
        let spacePinnedOrder = SpacePinnedOrderTransaction(
            folders: state.folders,
            pins: state.shortcutPins,
            mutations: mutations
        )
        let spacePinnedStructure = SpacePinnedStructureOwner(
            folders: state.folders,
            pins: state.shortcutPins,
            splitGroups: state.splitGroups,
            orderTransaction: spacePinnedOrder
        )
        let runtimeTeardown = TabRuntimeTeardownService(
            persistence: persistence,
            membership: membership,
            webViewSessions: webViewSessions
        )
        return Self(
            runtimePreparation: runtimePreparation,
            lookup: lookup,
            mutationPublisher: mutationPublisher,
            mutations: mutations,
            installer: installer,
            membership: membership,
            spacePinnedOrder: spacePinnedOrder,
            spacePinnedStructure: spacePinnedStructure,
            runtimeTeardown: runtimeTeardown
        )
    }
}
