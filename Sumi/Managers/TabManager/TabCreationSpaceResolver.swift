import Foundation

struct TabCreationSpaceResolution {
    let space: Space
    let defaultProfileID: UUID?
}

@MainActor
final class TabCreationSpaceResolver {
    private let spaces: TabSpaceCollectionStateOwner
    private let catalog: SpaceCatalogCommands
    private let profilePolicy: ProfileAssignmentPolicy

    init(
        spaces: TabSpaceCollectionStateOwner,
        catalog: SpaceCatalogCommands,
        profilePolicy: ProfileAssignmentPolicy
    ) {
        self.spaces = spaces
        self.catalog = catalog
        self.profilePolicy = profilePolicy
    }

    func resolve(
        preferred space: Space?,
        fallbackSpaceID: UUID?
    ) -> TabCreationSpaceResolution? {
        let profileIDs = profilePolicy.placementProfileIDs()
        let defaultProfileID = profileIDs.current ?? profileIDs.default
        guard let target = (
            space.flatMap { spaces.space(with: $0.id) }
                ?? fallbackSpaceID.flatMap { spaces.space(with: $0) }
                ?? ensureDefaultSpace(defaultProfileID: defaultProfileID)
        )
        else { return nil }
        return TabCreationSpaceResolution(
            space: target,
            defaultProfileID: defaultProfileID
        )
    }

    private func ensureDefaultSpace(defaultProfileID: UUID?) -> Space? {
        if let defaultProfileID,
           let profileSpace = spaces.first(where: {
               $0.profileId == defaultProfileID
           }) {
            return profileSpace
        }
        if defaultProfileID != nil,
           let unassignedSpace = spaces.first(where: { $0.profileId == nil }) {
            return unassignedSpace
        }
        if defaultProfileID == nil, let firstSpace = spaces.firstSpace {
            return firstSpace
        }

        precondition(
            spaces.count == 0,
            "Default Space provisioning requires an empty catalog"
        )
        return catalog.createSpaceIfAdmitted(
            name: DefaultSpaceConfiguration.name,
            icon: DefaultSpaceConfiguration.icon,
            workspaceTheme: DefaultSpaceConfiguration.makeTheme(),
            profileId: defaultProfileID
        )
    }
}
