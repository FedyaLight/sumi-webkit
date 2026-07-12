import Foundation

/// Ordered identity of one projected row in a sidebar drag source container.
enum SidebarDragSourceIdentity: Hashable {
    case pin(UUID)
    case tab(UUID)
    case folder(UUID)
    case splitGroup(UUID)
}

/// Pure membership matching for drag-source identity against pasteboard payload.
@MainActor
enum SidebarDragSourceMembership {
    static func matches(
        _ identity: SidebarDragSourceIdentity,
        sourceItemId: UUID,
        payload: DragOperation.Payload
    ) -> Bool {
        switch identity {
        case .pin(let pinId):
            return pinId == sourceItemId || payload.matchesShortcutPinId(pinId)
        case .tab(let tabId):
            return tabId == sourceItemId
        case .folder(let folderId):
            return folderId == sourceItemId || payload.matchesFolderId(folderId)
        case .splitGroup(let groupId):
            return groupId == sourceItemId || payload.matchesSplitGroupId(groupId)
        }
    }

    static func sourceIndex(
        in identities: [SidebarDragSourceIdentity],
        sourceItemId: UUID,
        payload: DragOperation.Payload
    ) -> Int? {
        identities.firstIndex {
            matches($0, sourceItemId: sourceItemId, payload: payload)
        }
    }
}

/// Live read model for sidebar drag source projection: container membership,
/// item counts, and identity-aware source indices used by same-container reorder.
@MainActor
protocol SidebarDragSourceInventorying: AnyObject {
    func sourceIdentities(for scope: SidebarDragScope) -> [SidebarDragSourceIdentity]?
}

@MainActor
extension SidebarDragSourceInventorying {
    func sourceContainerItemCount(for scope: SidebarDragScope) -> Int? {
        sourceIdentities(for: scope)?.count
    }

    func sourceIndex(
        for payload: DragOperation.Payload,
        scope: SidebarDragScope
    ) -> Int? {
        guard let identities = sourceIdentities(for: scope) else {
            return nil
        }
        return SidebarDragSourceMembership.sourceIndex(
            in: identities,
            sourceItemId: scope.sourceItemId,
            payload: payload
        )
    }
}

@MainActor
final class SidebarDragSourceInventory: SidebarDragSourceInventorying {
    private let essentialPins: ShortcutPinCollectionStateOwner
    private let splitOrdering: SplitGroupSidebarOrderingService
    private let regularTabs: RegularTabCollectionOwner
    private let folders: TabFolderCollectionStateOwner
    private let spacePinned: SpacePinnedStructureOwner

    init(
        essentialPins: ShortcutPinCollectionStateOwner,
        splitOrdering: SplitGroupSidebarOrderingService,
        regularTabs: RegularTabCollectionOwner,
        folders: TabFolderCollectionStateOwner,
        spacePinned: SpacePinnedStructureOwner
    ) {
        self.essentialPins = essentialPins
        self.splitOrdering = splitOrdering
        self.regularTabs = regularTabs
        self.folders = folders
        self.spacePinned = spacePinned
    }

    func sourceIdentities(for scope: SidebarDragScope) -> [SidebarDragSourceIdentity]? {
        switch scope.sourceContainer {
        case .essentials:
            return essentialPins.essentialPins(for: scope.profileId).map {
                .pin($0.id)
            }

        case .spacePinned(let spaceId):
            return splitOrdering.topLevelItems(for: spaceId).map(identity(from:))

        case .spaceRegular(let spaceId):
            return regularTabs.tabs(in: spaceId).map { .tab($0.id) }

        case .folder(let folderId):
            guard let spaceId = folders.spaceId(for: folderId) else {
                return nil
            }
            return spacePinned.folderChildVisualItems(for: folderId, in: spaceId)
                .map(identity(from:))

        case .none:
            return nil
        }
    }

    private func identity(from item: SplitGroupVisualListItem) -> SidebarDragSourceIdentity {
        switch item {
        case .folder(let folderId):
            return .folder(folderId)
        case .shortcut(let pinId):
            return .pin(pinId)
        case .splitGroup(let groupId):
            return .splitGroup(groupId)
        }
    }

    private func identity(
        from item: SpacePinnedStructureOwner.FolderChildVisualItem
    ) -> SidebarDragSourceIdentity {
        switch item {
        case .folder(let folderId):
            return .folder(folderId)
        case .shortcut(let pinId):
            return .pin(pinId)
        case .splitGroup(let groupId):
            return .splitGroup(groupId)
        }
    }
}

@MainActor
extension DragOperation.Payload {
    func matchesShortcutPinId(_ pinId: UUID) -> Bool {
        switch self {
        case .pin(let pin):
            return pin.id == pinId
        case .tab(let tab):
            return tab.shortcutPinId == pinId
        case .folder,
             .splitGroup:
            return false
        }
    }

    func matchesSplitGroupId(_ groupId: UUID) -> Bool {
        guard case .splitGroup(let group) = self else { return false }
        return group.id == groupId
    }

    func matchesFolderId(_ folderId: UUID) -> Bool {
        guard case .folder(let folder) = self else { return false }
        return folder.id == folderId
    }
}
