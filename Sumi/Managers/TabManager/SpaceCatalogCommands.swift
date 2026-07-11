import Foundation

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
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let persistence: TabStructuralPersistenceService
    private let defaultProfileID: @MainActor () -> UUID?
    private let announceChange: @MainActor () -> Void
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        transactions: TabStructuralLookupCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        persistence: TabStructuralPersistenceService,
        defaultProfileID: @escaping @MainActor () -> UUID?,
        announceChange: @escaping @MainActor () -> Void,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.transactions = transactions
        self.spaces = spaces
        self.structuralMutations = structuralMutations
        self.persistence = persistence
        self.defaultProfileID = defaultProfileID
        self.announceChange = announceChange
        self.notifications = notifications
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String = SumiPersistentGlyph.spaceDefaultIconValue,
        workspaceTheme: WorkspaceTheme? = nil,
        profileId: UUID? = nil
    ) -> Space {
        transactions.withTransaction {
            let resolvedProfileID = profileId ?? defaultProfileID()
            let resolvedTheme = workspaceTheme
                ?? SumiWorkspaceThemePresets.rotatingTheme(at: spaces.count)
            let space = Space(
                name: name,
                icon: icon,
                workspaceTheme: resolvedTheme,
                profileId: resolvedProfileID
            )

            if resolvedProfileID == nil {
                RuntimeDiagnostics.debug(
                    "Creating space '\(name)' without a resolved profile; profile reconciliation will run later.",
                    category: "SpaceCatalog"
                )
            }

            announceChange()
            spaces.append(space)
            persistence.markAllSpacesStructurallyDirty()
            structuralMutations.setTabs([], for: space.id)

            if spaces.currentSpace == nil {
                spaces.replaceCurrentSpace(space)
            }
            persistence.scheduleStructuralPersistence()
            return space
        }
    }

    @discardableResult
    func reorderSpace(spaceId: UUID, to targetIndex: Int) -> Bool {
        transactions.withTransaction {
            guard spaces.count > 1,
                  spaces.index(of: spaceId) != nil else {
                return false
            }

            announceChange()
            guard spaces.reorderSpace(
                spaceId: spaceId,
                to: targetIndex
            ) else {
                return false
            }

            persistence.markAllSpacesStructurallyDirty()
            persistence.scheduleStructuralPersistence()
            return true
        }
    }

    func renameSpace(spaceId: UUID, newName: String) throws {
        try transactions.withTransaction {
            guard let space = spaces.space(with: spaceId) else {
                throw CommandError.spaceNotFound(spaceId)
            }
            guard space.name != newName else { return }

            announceChange()
            spaces.renameSpace(spaceId: spaceId, to: newName)
            persistence.markAllSpacesStructurallyDirty()
            persistence.scheduleStructuralPersistence()
            notifications()?.presentSpaceRenamedNotification(name: newName)
        }
    }

    func updateSpaceIcon(spaceId: UUID, icon: String) throws {
        try transactions.withTransaction {
            guard spaces.space(with: spaceId) != nil else {
                throw CommandError.spaceNotFound(spaceId)
            }

            announceChange()
            spaces.updateIcon(spaceId: spaceId, to: icon)
            persistence.markAllSpacesStructurallyDirty()
            persistence.scheduleStructuralPersistence()
        }
    }
}
