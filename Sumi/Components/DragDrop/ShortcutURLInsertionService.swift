import Foundation
import SumiDomain

struct ShortcutURLPlacement {
    let role: ShortcutPinRole
    let profileID: UUID?
    let executionProfileID: UUID?
    let spaceID: UUID?
    let folderID: UUID?
    let index: Int
    let openTargetFolder: Bool
}

@MainActor
protocol ShortcutURLInserting: AnyObject {
    func insert(
        _ url: URL,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState
    ) -> Bool
}

@MainActor
final class ShortcutURLInsertionService: ShortcutURLInserting {
    private let store: ShortcutPinStoreOwner
    private let materializer: ShortcutTabMaterializer
    private let structuralLookup: TabStructuralLookupCoordinator
    private let prepareActivation:
        @MainActor (BrowserWindowState) -> (@MainActor (Tab) -> Void)?
    private let schedulePersistence: @MainActor () -> Void

    init(
        store: ShortcutPinStoreOwner,
        materializer: ShortcutTabMaterializer,
        structuralLookup: TabStructuralLookupCoordinator,
        prepareActivation: @escaping @MainActor (
            BrowserWindowState
        ) -> (@MainActor (Tab) -> Void)?,
        schedulePersistence: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.materializer = materializer
        self.structuralLookup = structuralLookup
        self.prepareActivation = prepareActivation
        self.schedulePersistence = schedulePersistence
    }

    func insert(
        _ url: URL,
        placement: ShortcutURLPlacement,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let activate = prepareActivation(windowState) else { return false }
        let proposedPin = ShortcutPin(
            id: UUID(),
            role: placement.role,
            profileId: placement.profileID,
            executionProfileId: placement.executionProfileID,
            spaceId: placement.spaceID,
            index: placement.index,
            folderId: placement.folderID,
            launchURL: url,
            title: url.host ?? url.absoluteString
        )

        let insertedPin: ShortcutPin? = structuralLookup.withTransaction {
            guard let insertedPin = store.insert(
                proposedPin,
                at: placement.index,
                openTargetFolder: placement.openTargetFolder
            ) else { return nil }
            let liveTab = materializer.materialize(
                insertedPin,
                in: windowState.id,
                currentSpaceId: windowState.currentSpaceId
            )
            _ = WindowTabSelectionStateApplicator.apply(
                liveTab,
                to: windowState,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
            structuralLookup.runAfterCurrentBatch {
                activate(liveTab)
            }
            return insertedPin
        }

        guard insertedPin != nil else { return false }
        schedulePersistence()
        return true
    }
}
