import Foundation
import SumiDomain

@MainActor
final class EssentialShortcutSpaceRebinder {
    enum Outcome {
        case notApplicable
        case rejected
        case committed
    }

    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let bindings: ShortcutTabBindingSynchronizer
    private let store: ShortcutPinStoreOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        resolution: ShortcutPinRuntimeResolutionOwner,
        bindings: ShortcutTabBindingSynchronizer,
        store: ShortcutPinStoreOwner,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.resolution = resolution
        self.bindings = bindings
        self.store = store
        self.structuralMutations = structuralMutations
    }

    func rebind(
        _ tab: Tab,
        source: ShortcutPin?,
        spaceID: UUID,
        index: Int
    ) -> Outcome {
        guard tab.isShortcutLiveInstance, let source else {
            return .notApplicable
        }
        guard source.role == .essential else { return .notApplicable }
        let detached = resolution.makeShortcutPin(
            from: tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: nil,
            index: index
        )
        guard bindings.canRebind(tab, from: source),
              let inserted = store.insert(detached, at: index) else {
            return .rejected
        }
        guard bindings.rebind(tab, from: source, to: inserted) else {
            store.removeFromContainers(inserted)
            return .rejected
        }
        structuralMutations.schedulePersistence()
        return .committed
    }
}
