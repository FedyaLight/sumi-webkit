import Foundation
import OSLog

enum TabStoreWrite: Sendable {
    case reconcile(TabPersistenceSnapshot, validating: Bool)
    case incremental(TabStructuralPersistenceDelta)
    case selection(TabPersistenceSelection)
    case runtimeState([TabRuntimeStateUpdate])
}

actor TabStoreWriteExecutor {
    private static let log = Logger.sumi(category: "TabPersistence")
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func execute(_ write: TabStoreWrite) throws {
        do {
            try database.transaction { transaction in
                switch write {
                case .reconcile(let snapshot, let validating):
                    if validating {
                        try TabSnapshotValidator.validateInput(snapshot)
                    }
                    try transaction.workspace.replaceAll(
                        spaces: try snapshot.spaces.map(TabDatabaseRecordTranslator.space),
                        folders: snapshot.folders.map(TabDatabaseRecordTranslator.folder),
                        tabs: try snapshot.tabs.map(TabDatabaseRecordTranslator.tab)
                    )
                    try transaction.workspace.save(
                        try TabDatabaseRecordTranslator.state(
                            snapshot.state,
                            splitGroups: snapshot.splitGroups,
                            existing: nil
                        )
                    )
                case .incremental(let delta):
                    try TabSnapshotValidator.validateDelta(delta)
                    let upsertedSpaceIDs = Set(delta.spaces.map(\.id))
                    let upsertedTabIDs = Set(delta.tabs.map(\.id))
                    let upsertedFolderIDs = Set(delta.folders.map(\.id))
                    try transaction.workspace.deleteSpaces(
                        ids: delta.deletedSpaceIds.subtracting(upsertedSpaceIDs)
                    )
                    try transaction.workspace.deleteTabs(
                        ids: delta.deletedTabIds.subtracting(upsertedTabIDs)
                    )
                    try transaction.workspace.deleteFolders(
                        ids: delta.deletedFolderIds.subtracting(upsertedFolderIDs)
                    )
                    for space in delta.spaces {
                        try transaction.workspace.save(
                            TabDatabaseRecordTranslator.space(space)
                        )
                    }
                    for folder in delta.folders {
                        try transaction.workspace.save(
                            TabDatabaseRecordTranslator.folder(folder)
                        )
                    }
                    for tab in delta.tabs {
                        try transaction.workspace.save(
                            TabDatabaseRecordTranslator.tab(tab)
                        )
                    }
                    try transaction.workspace.save(
                        try TabDatabaseRecordTranslator.state(
                            delta.state,
                            splitGroups: delta.splitGroups,
                            existing: try transaction.workspace.state()
                        )
                    )
                case .selection(let selection):
                    try transaction.workspace.save(
                        try TabDatabaseRecordTranslator.state(
                            selection,
                            splitGroups: nil,
                            existing: try transaction.workspace.state()
                        )
                    )
                case .runtimeState(let updates):
                    var latestByTabID: [UUID: TabRuntimeStateUpdate] = [:]
                    for update in updates {
                        latestByTabID[update.id] = update
                    }
                    for update in latestByTabID.values {
                        try transaction.workspace.updateRuntimeState(update)
                    }
                }
            }
        } catch {
            throw TabPersistenceErrorClassifier.classify(error)
        }
    }
}
