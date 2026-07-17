import Foundation
import SumiDomain

/// Mutates the ordered Space catalog and its user-editable metadata.
///
/// Cross-domain removal and selection handoff deliberately live elsewhere.
@MainActor
final class SpaceCatalogCommands {
    enum CommandError: LocalizedError {
        case spaceNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .spaceNotFound(let id):
                return "Space with id \(id.uuidString) was not found."
            }
        }
    }

    private let transactions: TabStructuralLookupCoordinator
    private let spaces: TabSpaceCollectionStateOwner
    private let creation: SpaceCreationTransaction
    private let runtimeConnection: TabRuntimePortConnection
    private let publication: SpaceCatalogMutationPublication

    init(
        transactions: TabStructuralLookupCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        creation: SpaceCreationTransaction,
        runtimeConnection: TabRuntimePortConnection,
        publication: SpaceCatalogMutationPublication
    ) {
        self.transactions = transactions
        self.spaces = spaces
        self.creation = creation
        self.runtimeConnection = runtimeConnection
        self.publication = publication
    }
    @discardableResult
    func createSpaceIfAdmitted(
        name: String,
        icon: String = SumiPersistentGlyph.spaceDefaultIconValue,
        workspaceTheme: WorkspaceTheme? = nil,
        profileId: UUID? = nil
    ) -> Space? {
        creation.create(
            name: name,
            icon: icon,
            workspaceTheme: workspaceTheme,
            profileID: profileId
        )
    }
    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        transactions.withTransaction {
            guard spaces.count > 1,
                  spaces.index(of: spaceId) != nil else {
                return false
            }

            publication.willMutate()
            guard spaces.reorderSpace(
                spaceId: spaceId,
                to: targetIndex
            ) else {
                return false
            }

            publication.didMutate(spaceID: spaceId, in: transactions)
            return true
        }
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        let runtimeLease = runtimeConnection.captureLease()
        try transactions.withTransaction {
            guard let space = spaces.space(with: spaceId) else {
                throw CommandError.spaceNotFound(spaceId)
            }
            guard space.name != newName else { return }

            publication.willMutate()
            spaces.renameSpace(spaceId: spaceId, to: newName)
            publication.didMutate(spaceID: spaceId, in: transactions)
            runtimeConnection.notifications(for: runtimeLease)?
                .presentSpaceRenamedNotification(name: newName)
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try transactions.withTransaction {
            guard spaces.space(with: spaceId) != nil else {
                throw CommandError.spaceNotFound(spaceId)
            }

            publication.willMutate()
            spaces.updateIcon(spaceId: spaceId, to: icon)
            publication.didMutate(spaceID: spaceId, in: transactions)
        }
    }
}
