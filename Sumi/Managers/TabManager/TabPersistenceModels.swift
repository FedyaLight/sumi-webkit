import Foundation
import SumiDomain

enum TabPersistedPageKind: String, Codable, Sendable {
    case web
    case empty
    case restoreFailure
}

struct TabPersistenceTab: Codable, Sendable {
    let id: UUID
    let urlString: String
    let name: String
    let index: Int
    let spaceId: UUID?
    let isPinned: Bool
    let isSpacePinned: Bool
    let profileId: UUID?
    let executionProfileId: UUID?
    let folderId: UUID?
    let iconAsset: String?
    let titleIsCustom: Bool
    let currentURLString: String?
    let canGoBack: Bool
    let canGoForward: Bool
    let pageKind: TabPersistedPageKind?

    init(
        id: UUID,
        urlString: String,
        name: String,
        index: Int,
        spaceId: UUID?,
        isPinned: Bool,
        isSpacePinned: Bool,
        profileId: UUID?,
        executionProfileId: UUID?,
        folderId: UUID?,
        iconAsset: String?,
        titleIsCustom: Bool = false,
        currentURLString: String?,
        canGoBack: Bool,
        canGoForward: Bool,
        pageKind: TabPersistedPageKind? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.name = name
        self.index = index
        self.spaceId = spaceId
        self.isPinned = isPinned
        self.isSpacePinned = isSpacePinned
        self.profileId = profileId
        self.executionProfileId = executionProfileId
        self.folderId = folderId
        self.iconAsset = iconAsset
        self.titleIsCustom = titleIsCustom
        self.currentURLString = currentURLString
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pageKind = pageKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        urlString = try container.decode(String.self, forKey: .urlString)
        name = try container.decode(String.self, forKey: .name)
        index = try container.decode(Int.self, forKey: .index)
        spaceId = try container.decodeIfPresent(UUID.self, forKey: .spaceId)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isSpacePinned = try container.decode(Bool.self, forKey: .isSpacePinned)
        profileId = try container.decodeIfPresent(UUID.self, forKey: .profileId)
        executionProfileId = try container.decodeIfPresent(
            UUID.self,
            forKey: .executionProfileId
        )
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        iconAsset = try container.decodeIfPresent(String.self, forKey: .iconAsset)
        titleIsCustom = try container.decodeIfPresent(
            Bool.self,
            forKey: .titleIsCustom
        ) ?? true
        currentURLString = try container.decodeIfPresent(
            String.self,
            forKey: .currentURLString
        )
        canGoBack = try container.decode(Bool.self, forKey: .canGoBack)
        canGoForward = try container.decode(Bool.self, forKey: .canGoForward)
        pageKind = try container.decodeIfPresent(
            TabPersistedPageKind.self,
            forKey: .pageKind
        )
    }
}

struct TabPersistenceFolder: Codable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let spaceId: UUID
    let parentFolderId: UUID?
    let isOpen: Bool
    let isLiveFolder: Bool
    let index: Int

    init(
        id: UUID,
        name: String,
        icon: String,
        color: String,
        spaceId: UUID,
        parentFolderId: UUID? = nil,
        isOpen: Bool,
        isLiveFolder: Bool = false,
        index: Int
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.spaceId = spaceId
        self.parentFolderId = parentFolderId
        self.isOpen = isOpen
        self.isLiveFolder = isLiveFolder
        self.index = index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        spaceId = try container.decode(UUID.self, forKey: .spaceId)
        parentFolderId = try container.decodeIfPresent(UUID.self, forKey: .parentFolderId)
        isOpen = try container.decode(Bool.self, forKey: .isOpen)
        isLiveFolder = try container.decodeIfPresent(
            Bool.self,
            forKey: .isLiveFolder
        ) ?? false
        index = try container.decode(Int.self, forKey: .index)
    }
}

struct TabPersistenceSpace: Codable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let index: Int
    let workspaceThemeData: Data?
    let profileId: UUID?
}

struct TabPersistenceSelection: Codable, Sendable {
    let currentTabID: UUID?
    let currentSpaceID: UUID?
}

struct TabPersistenceSnapshot: Codable, Sendable {
    let spaces: [TabPersistenceSpace]
    let tabs: [TabPersistenceTab]
    let folders: [TabPersistenceFolder]
    let splitGroups: [SplitGroup]
    let state: TabPersistenceSelection

    init(
        spaces: [TabPersistenceSpace],
        tabs: [TabPersistenceTab],
        folders: [TabPersistenceFolder],
        splitGroups: [SplitGroup] = [],
        state: TabPersistenceSelection
    ) {
        self.spaces = spaces
        self.tabs = tabs
        self.folders = folders
        self.splitGroups = splitGroups
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try container.decode([TabPersistenceSpace].self, forKey: .spaces)
        tabs = try container.decode([TabPersistenceTab].self, forKey: .tabs)
        folders = try container.decode([TabPersistenceFolder].self, forKey: .folders)
        splitGroups = try container.decodeIfPresent([SplitGroup].self, forKey: .splitGroups) ?? []
        state = try container.decode(TabPersistenceSelection.self, forKey: .state)
    }
}

struct TabStructuralPersistenceDelta: Sendable {
    let spaces: [TabPersistenceSpace]
    let tabs: [TabPersistenceTab]
    let folders: [TabPersistenceFolder]
    let splitGroups: [SplitGroup]?
    let deletedSpaceIds: Set<UUID>
    let deletedTabIds: Set<UUID>
    let deletedFolderIds: Set<UUID>
    let state: TabPersistenceSelection
}

struct TabRuntimeStateUpdate: Sendable {
    let id: UUID
    let urlString: String
    let currentURLString: String?
    let name: String
    let canGoBack: Bool
    let canGoForward: Bool

    let pageKind: TabPersistedPageKind?

    init(
        id: UUID,
        urlString: String,
        currentURLString: String?,
        name: String,
        canGoBack: Bool,
        canGoForward: Bool,
        pageKind: TabPersistedPageKind? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.currentURLString = currentURLString
        self.name = name
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.pageKind = pageKind
    }
}

enum TabPersistenceError: Error, Equatable {
    case concurrencyConflict
    case dataCorruption
    case storageFailure
    case rollbackFailed
    case invalidModelState
}
