import Foundation

struct TabCreationPlacement {
    let space: Space
    let temporaryProfileOverrideId: UUID?
    let effectiveProfileId: UUID?

    var admissionProfileIDs: Set<UUID> {
        effectiveProfileId.map { [$0] } ?? []
    }
}

/// Resolves and provisions the Space before a nil-profile backfill starts.
/// Stable Spaces remain inherited (`Tab.profileId == nil`); in-flight
/// transitions temporarily pin new followers to the pending profile until
/// commit. Installation always precedes deferred WebView work.
@MainActor
final class TabCreationPlacementService {
    private let spaceResolver: TabCreationSpaceResolver
    private let profileTransitions: SpaceProfileTransitionService
    private let membership: TabCollectionMembershipOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        catalog: SpaceCatalogCommands,
        profilePolicy: ProfileAssignmentPolicy,
        profileTransitions: SpaceProfileTransitionService,
        membership: TabCollectionMembershipOwner
    ) {
        self.spaceResolver = TabCreationSpaceResolver(
            spaces: spaces,
            catalog: catalog,
            profilePolicy: profilePolicy
        )
        self.profileTransitions = profileTransitions
        self.membership = membership
    }

    func withAdmittedCreationPlacement(
        preferred space: Space?,
        fallbackSpaceId: UUID? = nil,
        bootstrapProfileId: UUID? = nil,
        inheritsSpaceProfile: Bool = true,
        admission: (TabCreationPlacement) -> Bool,
        install: (TabCreationPlacement) -> Tab?
    ) -> Tab? {
        guard let resolution = spaceResolver.resolve(
            preferred: space,
            fallbackSpaceID: fallbackSpaceId
        ) else { return nil }
        let defaultProfileId = resolution.defaultProfileID
        let targetSpace = resolution.space
        let existingProfileId = targetSpace.profileId
        let inFlightProfileId = profileTransitions.lifecycle.inFlightProfileID(
            for: targetSpace.id
        )
        let desiredBootstrapProfileId = bootstrapProfileId ?? defaultProfileId
        let effectiveProfileId = inheritsSpaceProfile
            ? inFlightProfileId
                ?? existingProfileId
                ?? desiredBootstrapProfileId
            : bootstrapProfileId
        let placement = TabCreationPlacement(
            space: targetSpace,
            temporaryProfileOverrideId: inheritsSpaceProfile
                ? inFlightProfileId
                : nil,
            effectiveProfileId: effectiveProfileId
        )
        guard admission(placement), let tab = install(placement) else {
            return nil
        }
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

        guard existingProfileId == nil,
              let desiredProfileId = desiredBootstrapProfileId else {
            return tab
        }

        _ = profileTransitions.start(
            spaceID: targetSpace.id,
            profileID: desiredProfileId
        )
        return tab
    }
}
