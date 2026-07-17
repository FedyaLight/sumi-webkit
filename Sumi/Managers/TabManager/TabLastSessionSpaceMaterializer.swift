import Combine
import Foundation
import SumiDomain

@MainActor
final class TabLastSessionSpaceMaterializer {
    private let spaces: TabSpaceCollectionStateOwner
    private let persistence: TabStructuralPersistenceService
    private let changes: ObservableObjectPublisher

    init(
        spaces: TabSpaceCollectionStateOwner,
        persistence: TabStructuralPersistenceService,
        changes: ObservableObjectPublisher
    ) {
        self.spaces = spaces
        self.persistence = persistence
        self.changes = changes
    }

    func materialize(
        _ plan: TabLastSessionMergePlan,
        existing: [UUID: Space]
    ) -> [UUID: Space] {
        var spacesByID = existing
        let orderedSpaces = plan.orderedSpaceIds.compactMap { spaceID -> Space? in
            guard let restored = plan.restoredSpacesById[spaceID] else {
                return existing[spaceID]
            }
            let theme = restored.workspaceThemeData
                .flatMap(WorkspaceTheme.decode) ?? .default
            if let space = existing[spaceID] {
                space.name = restored.name
                space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(
                    restored.icon
                )
                space.workspaceTheme = theme
                return space
            }
            let space = Space(
                id: restored.id,
                name: restored.name,
                icon: restored.icon,
                workspaceTheme: theme,
                profileId: restored.profileId
            )
            spacesByID[space.id] = space
            return space
        }
        changes.send()
        spaces.replaceSpaces(orderedSpaces)
        persistence.markAllSpacesStructurallyDirty()
        return spacesByID
    }
}
