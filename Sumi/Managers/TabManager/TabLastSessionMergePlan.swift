import Foundation

struct TabLastSessionLiveState {
    struct SpaceReference {
        let id: UUID
        let profileId: UUID?
    }

    struct FolderReference {
        let id: UUID
        let spaceId: UUID
        let parentFolderId: UUID?
        let index: Int
    }

    struct RegularTabReference {
        let id: UUID
        let index: Int
    }

    let spaces: [SpaceReference]
    let currentSpaceId: UUID?
    let foldersBySpace: [UUID: [FolderReference]]
    let favoritePinsByProfile: [UUID: [TabLastSessionShortcutDescriptor]]
    let spacePinnedShortcuts: [UUID: [TabLastSessionShortcutDescriptor]]
    let regularTabsBySpace: [UUID: [RegularTabReference]]

    var allPersistedItemIds: Set<UUID> {
        var ids = Set(foldersBySpace.values.joined().map(\.id))
        ids.formUnion(favoritePinsByProfile.values.joined().map(\.id))
        ids.formUnion(spacePinnedShortcuts.values.joined().map(\.id))
        ids.formUnion(regularTabsBySpace.values.joined().map(\.id))
        return ids
    }
}

struct TabLastSessionFolderPlacement {
    let id: UUID
    let spaceId: UUID
    let parentFolderId: UUID?
    let index: Int
    let restoredValues: TabPersistenceFolder?
}

enum TabLastSessionShortcutKind: Equatable {
    case favorite
    case spacePinned
}

struct TabLastSessionShortcutDescriptor {
    let id: UUID
    let kind: TabLastSessionShortcutKind
    let profileId: UUID?
    let executionProfileId: UUID?
    let spaceId: UUID?
    let index: Int
    let folderId: UUID?
    let launchURL: URL
    let title: String
    let iconAsset: String?
    var titleIsCustom: Bool = false

    func placed(at index: Int) -> Self {
        Self(
            id: id,
            kind: kind,
            profileId: profileId,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset,
            titleIsCustom: titleIsCustom
        )
    }
}

struct TabLastSessionRestoredTab {
    let id: UUID
    let url: URL
    let name: String
    let spaceId: UUID
    let index: Int
    let profileId: UUID?
    let canGoBack: Bool
    let canGoForward: Bool
    let isRestoreFailure: Bool
    let restoreFailureRawDestination: String?
    let restoreFailureDestination: URL?
}

enum TabLastSessionRegularTabPlacement {
    case existing(id: UUID, spaceId: UUID, index: Int)
    case restored(TabLastSessionRestoredTab)

    var id: UUID {
        switch self {
        case .existing(let id, _, _): id
        case .restored(let tab): tab.id
        }
    }

    var index: Int {
        switch self {
        case .existing(_, _, let index): index
        case .restored(let tab): tab.index
        }
    }
}

enum TabLastSessionSpaceSelection {
    case keepCurrent
    case select(UUID?)
}

struct TabLastSessionMergePlan {
    let orderedSpaceIds: [UUID]
    let restoredSpacesById: [UUID: TabPersistenceSpace]
    let foldersBySpace: [UUID: [TabLastSessionFolderPlacement]]
    let favoritePinsByProfile: [UUID: [TabLastSessionShortcutDescriptor]]
    let spacePinnedShortcuts: [UUID: [TabLastSessionShortcutDescriptor]]
    let regularTabsBySpace: [UUID: [TabLastSessionRegularTabPlacement]]
    let spaceSelection: TabLastSessionSpaceSelection
    let requestedCurrentTabId: UUID?
    let lazyRestoredTabIds: Set<UUID>
}
