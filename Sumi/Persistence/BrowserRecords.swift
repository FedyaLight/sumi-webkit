import Foundation
import GRDB

struct ProfileRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profiles"

    let id: UUID
    var name: String
    var index: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case index = "position"
    }
}

struct SpaceRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "spaces"

    let id: UUID
    let profileID: UUID
    var name: String
    var icon: String
    var index: Int
    var workspaceThemeData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case name
        case icon
        case index = "position"
        case workspaceThemeData = "workspace_theme"
    }
}

struct FolderRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"

    let id: UUID
    let spaceID: UUID
    var parentFolderID: UUID?
    var name: String
    var icon: String
    var color: String
    var isOpen: Bool
    var isLiveFolder: Bool
    var index: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceID = "space_id"
        case parentFolderID = "parent_folder_id"
        case name
        case icon
        case color
        case isOpen = "is_open"
        case isLiveFolder = "is_live"
        case index = "position"
    }
}

struct TabRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tabs"

    let id: UUID
    let profileID: UUID?
    var executionProfileID: UUID?
    var spaceID: UUID?
    var folderID: UUID?
    var urlString: String
    var name: String
    var isPinned: Bool
    var isSpacePinned: Bool
    var index: Int
    var iconAsset: String?
    var titleIsCustom: Bool
    var currentURLString: String
    var canGoBack: Bool
    var canGoForward: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case executionProfileID = "execution_profile_id"
        case spaceID = "space_id"
        case folderID = "folder_id"
        case urlString = "url"
        case name
        case isPinned = "is_pinned"
        case isSpacePinned = "is_space_pinned"
        case index = "position"
        case iconAsset = "icon_asset"
        case titleIsCustom = "title_is_custom"
        case currentURLString = "current_url"
        case canGoBack = "can_go_back"
        case canGoForward = "can_go_forward"
    }
}

struct BookmarkRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookmarks"

    let id: UUID
    var parentID: UUID?
    var name: String
    var urlString: String?
    var kind: String
    var index: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case name
        case urlString = "url"
        case kind
        case index = "position"
    }
}

struct TabStateRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tab_state"

    let id: Int
    var currentTabID: UUID?
    var currentSpaceID: UUID?
    var splitGroupsData: Data?

    init(
        currentTabID: UUID?,
        currentSpaceID: UUID?,
        splitGroupsData: Data?
    ) {
        id = 1
        self.currentTabID = currentTabID
        self.currentSpaceID = currentSpaceID
        self.splitGroupsData = splitGroupsData
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case currentTabID = "current_tab_id"
        case currentSpaceID = "current_space_id"
        case splitGroupsData = "split_groups"
    }
}

struct ProfileRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func all() throws -> [ProfileRecord] {
        try ProfileRecord
            .order(Column("position"))
            .fetchAll(database)
    }

    func save(_ record: ProfileRecord) throws {
        try record.save(database)
    }

    func delete(id: UUID) throws {
        _ = try ProfileRecord.deleteOne(database, key: id)
    }

    func replaceAll(with records: [ProfileRecord]) throws {
        _ = try ProfileRecord.deleteAll(database)
        for record in records {
            try record.insert(database)
        }
    }
}

struct WorkspaceRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func spaces() throws -> [SpaceRecord] {
        try SpaceRecord
            .order(Column("position"))
            .fetchAll(database)
    }

    func tabs() throws -> [TabRecord] {
        try TabRecord
            .order(Column("position"))
            .fetchAll(database)
    }

    func folders() throws -> [FolderRecord] {
        try FolderRecord
            .order(Column("position"))
            .fetchAll(database)
    }

    func state() throws -> TabStateRecord? {
        try TabStateRecord.fetchOne(database, key: 1)
    }

    func save(_ record: SpaceRecord) throws {
        try record.save(database)
    }

    func save(_ record: TabRecord) throws {
        try record.save(database)
    }

    func save(_ record: FolderRecord) throws {
        try record.save(database)
    }

    func save(_ record: TabStateRecord) throws {
        try record.save(database)
    }

    func deleteTabs(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        _ = try TabRecord.filter(ids.contains(Column("id"))).deleteAll(database)
    }

    func deleteFolders(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        _ = try FolderRecord.filter(ids.contains(Column("id"))).deleteAll(database)
    }

    func deleteSpaces(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        _ = try SpaceRecord.filter(ids.contains(Column("id"))).deleteAll(database)
    }

    func updateRuntimeState(_ update: TabRuntimeStateUpdate) throws {
        guard var tab = try TabRecord.fetchOne(database, key: update.id) else {
            return
        }
        tab.urlString = update.urlString
        tab.currentURLString = update.currentURLString ?? update.urlString
        tab.name = update.name
        tab.canGoBack = update.canGoBack
        tab.canGoForward = update.canGoForward
        try tab.update(database)
    }

    func replaceAll(
        spaces: [SpaceRecord],
        folders: [FolderRecord],
        tabs: [TabRecord]
    ) throws {
        _ = try TabRecord.deleteAll(database)
        _ = try FolderRecord.deleteAll(database)
        _ = try SpaceRecord.deleteAll(database)
        for record in spaces {
            try record.insert(database)
        }
        for record in folders {
            try record.insert(database)
        }
        for record in tabs {
            try record.insert(database)
        }
    }
}

struct BookmarkRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func all() throws -> [BookmarkRecord] {
        try BookmarkRecord
            .order(Column("parent_id"), Column("position"))
            .fetchAll(database)
    }

    func append(_ records: [BookmarkRecord]) throws {
        for record in records {
            try record.insert(database)
        }
    }

    func save(_ record: BookmarkRecord) throws {
        try record.save(database)
    }

    func deleteAll() throws {
        _ = try BookmarkRecord.deleteAll(database)
    }

    func replaceAll(with records: [BookmarkRecord]) throws {
        _ = try BookmarkRecord.deleteAll(database)
        var remaining = records
        var insertedIDs = Set<UUID>()
        while remaining.isEmpty == false {
            let ready = remaining.filter {
                $0.parentID == nil || insertedIDs.contains($0.parentID!)
            }
            guard ready.isEmpty == false else {
                throw SumiDatabaseError.invalidIdentifier(
                    "Bookmark hierarchy contains a missing parent or cycle"
                )
            }
            for record in ready {
                try record.insert(database)
                insertedIDs.insert(record.id)
            }
            let readyIDs = Set(ready.map(\.id))
            remaining.removeAll { readyIDs.contains($0.id) }
        }
    }
}
