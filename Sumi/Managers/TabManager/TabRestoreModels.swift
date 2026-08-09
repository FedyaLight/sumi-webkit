import Foundation
import SumiDomain

struct TabRestoreSpaceDTO: Sendable {
    let id: UUID
    let name: String
    let icon: String
    let workspaceTheme: WorkspaceTheme
    let profileId: UUID?
}

struct TabRestoreTabDTO: Sendable {
    let id: UUID
    let url: URL
    let name: String
    let index: Int
    let spaceId: UUID
    let profileId: UUID?
    let folderId: UUID?
    let canGoBack: Bool
    let canGoForward: Bool
    var isRestoreFailure = false
    var restoreFailureDestination: URL? = nil
    var restoreFailureRawDestination: String? = nil
}

struct TabRestoreShortcutDTO: Sendable {
    let id: UUID
    let role: ShortcutPinRole
    let profileId: UUID?
    let executionProfileId: UUID?
    let spaceId: UUID?
    let index: Int
    let folderId: UUID?
    let launchURL: URL
    let title: String
    let iconAsset: String?
    var titleIsCustom: Bool = false
}

struct TabRestorePayload: Sendable {
    let spaces: [TabRestoreSpaceDTO]
    let regularTabsBySpace: [UUID: [TabRestoreTabDTO]]
    let foldersBySpace: [UUID: [TabPersistenceFolder]]
    let pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]]
    let pendingPinnedShortcuts: [TabRestoreShortcutDTO]
    let spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]]
    let splitGroups: [SplitGroup]
    let currentSpaceId: UUID?
    let currentTabId: UUID?
    let snapshot: TabPersistenceSnapshot
    let repairReasons: [String]
    let totalTabCount: Int
    let pinnedCount: Int
    let spacePinnedCount: Int
    let regularCount: Int
}

protocol TabRestorePayloadLoading: Sendable {
    func load(defaultProfileId: UUID?) async throws -> TabRestorePayload
}

struct TabRestoreStoreRecords: Sendable {
    let spaces: [TabRestoreSpaceRecord]
    let tabs: [TabRestoreTabRecord]
    let folders: [TabRestoreFolderRecord]
    let states: [TabRestoreStateRecord]
}

struct TabRestoreSpaceRecord: Sendable {
    let id: UUID
    let name: String
    let icon: String
    let index: Int
    let workspaceThemeData: Data?
    let profileId: UUID?
}

struct TabRestoreTabRecord: Sendable {
    let id: UUID
    let urlString: String
    let name: String
    let isPinned: Bool
    let isSpacePinned: Bool
    let index: Int
    let spaceId: UUID?
    let profileId: UUID?
    let executionProfileId: UUID?
    let folderId: UUID?
    let iconAsset: String?
    var titleIsCustom: Bool = false
    let currentURLString: String?
    let canGoBack: Bool
    let canGoForward: Bool
    var pageKind: TabPersistedPageKind? = nil
}

struct TabRestoreFolderRecord: Sendable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let spaceId: UUID
    let parentFolderId: UUID?
    let isOpen: Bool
    var isLiveFolder: Bool = false
    let index: Int
}

struct TabRestoreStateRecord: Sendable {
    let currentTabID: UUID?
    let currentSpaceID: UUID?
    let splitGroupsData: Data?
}

struct TabRestoreCategorizedTabs: Sendable {
    var regularTabsBySpace: [UUID: [TabRestoreTabDTO]]
    var pinnedShortcutsByProfile: [UUID: [TabRestoreShortcutDTO]]
    var pendingPinnedShortcuts: [TabRestoreShortcutDTO]
    var spacePinnedShortcutsBySpace: [UUID: [TabRestoreShortcutDTO]]
    var pinnedCount: Int
    var spacePinnedCount: Int
    var regularCount: Int
}
