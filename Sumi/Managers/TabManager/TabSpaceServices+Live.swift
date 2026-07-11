import Foundation

extension TabSpaceServices {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        let activation = SpaceActivationService(
            state: tabManager.stateStore,
            projection: tabManager.spaceLauncherProjection,
            persistence: tabManager.structuralPersistence,
            profileIds: { [weak tabManager] in
                (
                    current: tabManager?.runtimePorts?.currentProfileId,
                    default: tabManager?.runtimePorts?.defaultProfileId
                )
            },
            assignSpaceProfile: { [weak tabManager] spaceId, profileId in
                tabManager?.profileAssignments.spaces.assign(
                    spaceID: spaceId,
                    toProfile: profileId
                ) ?? .failed
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner
                    .activeEssentialTabs(for: profileId) ?? []
            }
        )
        let catalog = SpaceCatalogCommands(
            transactions: tabManager.structuralLookupCoordinator,
            spaces: tabManager.spaceStateOwner,
            structuralMutations: tabManager.structuralCollectionMutationOwner,
            persistence: tabManager.structuralPersistence,
            defaultProfileID: { [weak tabManager] in
                tabManager?.runtimePorts?.defaultProfileId
            },
            announceChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            notifications: { [weak tabManager] in
                tabManager?.runtimePorts?.notifications()
            }
        )
        let placement = TabCreationPlacementService(
            spaces: tabManager.spaceStateOwner,
            catalog: catalog,
            profilePolicy: tabManager.profileAssignments.policy,
            profileTransitions: tabManager.profileAssignments.spaces,
            membership: tabManager.tabCollectionMembershipOwner
        )
        let removal = SpaceRemovalService(
            state: tabManager.stateStore,
            persistence: tabManager.structuralPersistence,
            transactions: tabManager.structuralLookupCoordinator,
            contentRetirement: SpaceContentRetirementService(
                state: tabManager.stateStore,
                structuralMutations: tabManager.structuralCollectionMutationOwner,
                splitGroups: SpaceSplitGroupRetirementService(
                    store: tabManager.splitGroupStore,
                    mutations: tabManager.splitGroupMutations
                ),
                liveShortcutTabs: tabManager.liveShortcutTabs,
                runtimeTeardown: tabManager.runtimeTeardown
            ),
            windowStates: DeletedSpaceWindowStateReconciler(
                runtimePorts: { [weak tabManager] in
                    guard let tabManager else {
                        preconditionFailure(
                            "Space window reconciliation used after TabManager deallocation"
                        )
                    }
                    return tabManager.requireRuntimePorts()
                }
            ),
            announceChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            }
        )
        return Self(
            catalog: catalog,
            removal: removal,
            activation: activation,
            placement: placement
        )
    }
}
