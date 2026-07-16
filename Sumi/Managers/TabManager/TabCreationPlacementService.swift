import Foundation

struct TabCreationPlacement {
    let space: Space
    let temporaryProfileOverrideId: UUID?
}

/// Resolves and provisions the Space before a nil-profile backfill starts.
/// Stable Spaces remain inherited (`Tab.profileId == nil`); in-flight
/// transitions temporarily pin new followers to the pending profile until
/// commit. Installation always precedes deferred WebView work.
@MainActor
final class TabCreationPlacementService {
    private let spaces: TabSpaceCollectionStateOwner
    private let catalog: SpaceCatalogCommands
    private let profilePolicy: ProfileAssignmentPolicy
    private let profileTransitions: SpaceProfileTransitionService
    private let membership: TabCollectionMembershipOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        catalog: SpaceCatalogCommands,
        profilePolicy: ProfileAssignmentPolicy,
        profileTransitions: SpaceProfileTransitionService,
        membership: TabCollectionMembershipOwner
    ) {
        self.spaces = spaces
        self.catalog = catalog
        self.profilePolicy = profilePolicy
        self.profileTransitions = profileTransitions
        self.membership = membership
    }

    private func resolveTargetSpace(
        preferred space: Space?,
        fallbackSpaceId: UUID? = nil
    ) -> Space {
        space.flatMap { spaces.space(with: $0.id) }
            ?? fallbackSpaceId.flatMap { spaces.space(with: $0) }
            ?? ensureDefaultSpaceIfNeeded()
    }

    func withCreationPlacement(
        preferred space: Space?,
        fallbackSpaceId: UUID? = nil,
        bootstrapProfileId: UUID? = nil,
        inheritsSpaceProfile: Bool = true,
        install: (TabCreationPlacement) -> Tab
    ) -> Tab {
        let targetSpace = resolveTargetSpace(
            preferred: space,
            fallbackSpaceId: fallbackSpaceId
        )
        let existingProfileId = targetSpace.profileId
        let inFlightProfileId = profileTransitions.lifecycle.inFlightProfileID(
            for: targetSpace.id
        )
        let tab = install(
            TabCreationPlacement(
                space: targetSpace,
                temporaryProfileOverrideId: inheritsSpaceProfile
                    ? inFlightProfileId
                    : nil
            )
        )
        precondition(
            membership.allTabs().contains { candidate in
                candidate === tab && candidate.spaceId == targetSpace.id
            },
            "Creation placement must install its Tab before profile assignment"
        )

        if let inFlightProfileId {
            if inheritsSpaceProfile {
                precondition(
                    tab.profileId == inFlightProfileId,
                    "In-flight Space followers must be pinned before materialization"
                )
                precondition(
                    profileTransitions.lifecycle.registerCreationFollower(
                        tab,
                        in: targetSpace.id,
                        profileID: inFlightProfileId
                    ),
                    "In-flight Space transition changed during Tab installation"
                )
            }
            return tab
        }

        let desiredProfileId = bootstrapProfileId
            ?? defaultProfileIDForSpaceBootstrap
        guard existingProfileId == nil, let desiredProfileId else {
            return tab
        }

        _ = profileTransitions.start(
            spaceID: targetSpace.id,
            profileID: desiredProfileId
        )
        return tab
    }

    private var defaultProfileIDForSpaceBootstrap: UUID? {
        let profileIDs = profilePolicy.placementProfileIDs()
        return profileIDs.current ?? profileIDs.default
    }

    private func ensureDefaultSpaceIfNeeded() -> Space {
        let profileID = defaultProfileIDForSpaceBootstrap
        if let profileID,
           let profileSpace = spaces.first(where: { $0.profileId == profileID }) {
            return profileSpace
        }

        if profileID != nil,
           let unassignedSpace = spaces.first(where: { $0.profileId == nil }) {
            return unassignedSpace
        }

        if profileID == nil,
           let firstSpace = spaces.firstSpace {
            return firstSpace
        }

        precondition(spaces.count == 0, "Personal Space provisioning requires an empty catalog")
        return catalog.createSpace(
            name: "Personal",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            workspaceTheme: .default,
            profileId: profileID
        )
    }
}
