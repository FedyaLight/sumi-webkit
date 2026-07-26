import Foundation
import SumiDomain

/// Converts or reorders one split group as one sidebar item. Durable member
/// residence and the group's container publish atomically.
@MainActor
final class SplitGroupContainerConversion {
    private let ordering: SplitGroupSidebarOrderingService
    private let mutations: SplitGroupMutationService
    private let folders: TabFolderCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let shortcutMoves: SplitGroupShortcutMoveService
    private let shortcutToRegular: ShortcutPinToRegularTabService
    private let essentialsVisualOrder: EssentialsVisualOrderTransaction

    init(
        ordering: SplitGroupSidebarOrderingService,
        mutations: SplitGroupMutationService,
        folders: TabFolderCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        shortcutMoves: SplitGroupShortcutMoveService,
        shortcutToRegular: ShortcutPinToRegularTabService,
        essentialsVisualOrder: EssentialsVisualOrderTransaction
    ) {
        self.ordering = ordering
        self.mutations = mutations
        self.folders = folders
        self.regularTabs = regularTabs
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.launcherPlacement = launcherPlacement
        self.shortcutMoves = shortcutMoves
        self.shortcutToRegular = shortcutToRegular
        self.essentialsVisualOrder = essentialsVisualOrder
    }

    @discardableResult
    func move(groupID: UUID, operation: DragOperation) -> Bool {
        guard let group = ordering.group(id: groupID),
              sourceContainerMatches(group.container, operation.fromContainer)
        else { return false }

        if case .essentialSidebar(let ownerProfileID, _) = group.container,
           operation.toContainer == .essentials,
           let profileID = ownerProfileID ?? operation.scope.profileId {
            return essentialsVisualOrder.reorder(
                .splitGroup(group.id),
                for: profileID,
                to: operation.toIndex
            )
        }

        switch operation.toContainer {
        case .essentials:
            guard let profileID = operation.scope.profileId else { return false }
            let container = SplitGroupContainer.essentialSidebar(
                profileId: profileID,
                index: operation.toIndex
            )
            if case .regularTabs = group.container {
                return moveRegularGroup(
                    group,
                    to: container,
                    destination: TabShortcutPinDestination(
                        role: .essential,
                        profileId: profileID,
                        spaceId: nil,
                        folderId: nil,
                        index: operation.toIndex,
                        opensFolder: false
                    ),
                    preferredWindowID: operation.scope.windowId
                )
            }
            return moveLauncherGroup(group, to: container) { _, offset in
                ShortcutSplitLauncherDestination(
                    role: .essential,
                    profileId: profileID,
                    spaceId: nil,
                    folderId: nil,
                    index: operation.toIndex + offset,
                    opensFolder: false
                )
            }

        case .spacePinned(let spaceID):
            let container = SplitGroupContainer.shortcutSidebar(
                spaceId: spaceID,
                profileId: operation.scope.profileId,
                folderId: nil,
                index: operation.toIndex
            )
            if case .regularTabs = group.container {
                return moveRegularGroup(
                    group,
                    to: container,
                    destination: TabShortcutPinDestination(
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: spaceID,
                        folderId: nil,
                        index: operation.toIndex,
                        opensFolder: false
                    ),
                    preferredWindowID: operation.scope.windowId
                )
            }
            if case .shortcutSidebar(let sourceSpaceID, _, nil, _) = group.container,
               sourceSpaceID == spaceID {
                return spacePinnedVisualOrder.reorder(
                    .splitGroup(group.id),
                    in: spaceID,
                    to: operation.toIndex
                )
            }
            return moveLauncherGroup(group, to: container) { _, offset in
                ShortcutSplitLauncherDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceID,
                    folderId: nil,
                    index: operation.toIndex + offset,
                    opensFolder: false
                )
            }

        case .folder(let folderID):
            guard let spaceID = folders.spaceId(for: folderID) else { return false }
            if group.container.shortcutSidebarFolderId == folderID,
               group.container.spaceId == spaceID {
                return spacePinnedVisualOrder.reorder(
                    .splitGroup(group.id),
                    in: spaceID,
                    folderID: folderID,
                    to: operation.toIndex
                )
            }
            let index = operation.toIndex
            let container = SplitGroupContainer.shortcutSidebar(
                spaceId: spaceID,
                profileId: operation.scope.profileId,
                folderId: folderID,
                index: index
            )
            if case .regularTabs = group.container {
                return moveRegularGroup(
                    group,
                    to: container,
                    destination: TabShortcutPinDestination(
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: spaceID,
                        folderId: folderID,
                        index: index,
                        opensFolder: false
                    ),
                    preferredWindowID: operation.scope.windowId
                )
            }
            return moveLauncherGroup(group, to: container) { _, offset in
                ShortcutSplitLauncherDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceID,
                    folderId: folderID,
                    index: index + offset,
                    opensFolder: false
                )
            }

        case .spaceRegular(let spaceID):
            if group.container.isShortcutSidebar {
                return shortcutToRegular.convertGroup(
                    group,
                    into: spaceID,
                    at: operation.toIndex,
                    preferredWindowID: operation.scope.windowId
                )
            }
            guard case .regularTabs(let sourceSpaceID) = group.container,
                  sourceSpaceID == spaceID,
                  let rawIndex = regularGroupRawInsertionIndex(
                      for: group,
                      in: spaceID,
                      proposedModelIndex: operation.toIndex
                  ) else { return false }
            let memberIDs = Set(group.memberIDs.compactMap { memberID -> UUID? in
                guard case .regularTab(let tabID) = memberID else { return nil }
                return tabID
            })
            return regularTabs.reorderSplitGroup(
                memberIDs: memberIDs,
                in: spaceID,
                toRawIndex: rawIndex
            )

        case .none:
            return false
        }
    }

    private func moveLauncherGroup(
        _ group: SplitGroup,
        to container: SplitGroupContainer,
        destination: (ShortcutPin, Int) -> ShortcutSplitLauncherDestination?
    ) -> Bool {
        guard isLauncherContainer(group.container),
              let replacement = group.changingContainer(to: container),
              replacement != group,
              let moves = launcherPlacement.prepareMoves(
                  for: group,
                  destination: destination
              ) else { return false }
        return mutations.replaceAtomically(
            group,
            with: replacement,
            applying: { moves.applyAndCommit() }
        )
    }

    private func moveRegularGroup(
        _ group: SplitGroup,
        to container: SplitGroupContainer,
        destination: TabShortcutPinDestination,
        preferredWindowID: UUID?
    ) -> Bool {
        guard case .regularTabs = group.container else { return false }
        let members = group.memberIDs.compactMap { memberID -> Tab? in
            guard case .regularTab(let tabID) = memberID,
                  let tab = regularTabs.tab(for: tabID) else { return nil }
            return tab
        }
        guard members.count == group.memberIDs.count else { return false }
        return shortcutMoves.move(
            group,
            tabs: members,
            to: container,
            destination: destination,
            preferredWindowID: preferredWindowID
        )
    }

    private func regularGroupRawInsertionIndex(
        for group: SplitGroup,
        in spaceID: UUID,
        proposedModelIndex: Int
    ) -> Int? {
        SidebarVisualSceneProjection.regularRawInsertionIndex(
            movingGroupID: group.id,
            atModelBoundary: proposedModelIndex,
            rows: SidebarVisualSceneProjection.regularRun(
                tabIDs: regularTabs.tabs(in: spaceID).map(\.id),
                groups: ordering.regularGroups(for: spaceID)
            ).rows
        )
    }

    private func sourceContainerMatches(
        _ container: SplitGroupContainer,
        _ dragContainer: TabDragManager.DragContainer
    ) -> Bool {
        switch (container, dragContainer) {
        case (.regularTabs(let spaceID), .spaceRegular(let draggedSpaceID)):
            return spaceID == draggedSpaceID
        case (.essentialSidebar, .essentials):
            return true
        case (.shortcutSidebar(let spaceID, _, nil, _), .spacePinned(let draggedSpaceID)):
            return spaceID == draggedSpaceID
        case (.shortcutSidebar(_, _, let folderID?, _), .folder(let draggedFolderID)):
            return folderID == draggedFolderID
        default:
            return false
        }
    }

    private func isLauncherContainer(_ container: SplitGroupContainer) -> Bool {
        switch container {
        case .essentialSidebar, .shortcutSidebar:
            return true
        case .regularTabs:
            return false
        }
    }
}
