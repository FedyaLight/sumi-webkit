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
    private let transaction: ShortcutURLInsertionTransaction
    private let prepareActivation:
        @MainActor (BrowserWindowState) -> (@MainActor (Tab) -> Void)?
    private let schedulePersistence: @MainActor () -> Void

    init(
        transaction: ShortcutURLInsertionTransaction,
        prepareActivation: @escaping @MainActor (
            BrowserWindowState
        ) -> (@MainActor (Tab) -> Void)?,
        schedulePersistence: @escaping @MainActor () -> Void
    ) {
        self.transaction = transaction
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

        guard transaction.insert(
            proposedPin,
            placement: placement,
            in: windowState,
            activate: activate
        ) else { return false }
        schedulePersistence()
        return true
    }
}
