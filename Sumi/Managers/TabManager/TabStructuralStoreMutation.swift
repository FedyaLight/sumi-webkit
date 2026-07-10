import Foundation
import SwiftData

enum TabStructuralStoreMutation {
    static func reconcile(
        _ snapshot: TabPersistenceSnapshot,
        validating: Bool,
        in context: ModelContext
    ) throws {
        if validating {
            try TabSnapshotValidator.validateInput(snapshot)
        }

        let allTabs = try context.fetch(FetchDescriptor<TabEntity>())
        let keptTabIds = Set(snapshot.tabs.map(\.id))
        for tab in allTabs where keptTabIds.contains(tab.id) == false {
            context.delete(tab)
        }
        let tabsById = Dictionary(allTabs.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for tab in snapshot.tabs {
            TabStoreRecordMutation.upsert(tab, existing: tabsById[tab.id], in: context)
        }

        let allFolders = try context.fetch(FetchDescriptor<FolderEntity>())
        let keptFolderIds = Set(snapshot.folders.map(\.id))
        for folder in allFolders where keptFolderIds.contains(folder.id) == false {
            context.delete(folder)
        }
        let foldersById = Dictionary(
            allFolders.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for folder in snapshot.folders {
            TabStoreRecordMutation.upsert(folder, existing: foldersById[folder.id], in: context)
        }

        let allSpaces = try context.fetch(FetchDescriptor<SpaceEntity>())
        let keptSpaceIds = Set(snapshot.spaces.map(\.id))
        for space in allSpaces where keptSpaceIds.contains(space.id) == false {
            context.delete(space)
        }
        let spacesById = Dictionary(
            allSpaces.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for space in snapshot.spaces {
            TabStoreRecordMutation.upsert(space, existing: spacesById[space.id], in: context)
        }

        try TabStoreRecordMutation.upsertSelection(
            snapshot.state,
            splitGroups: snapshot.splitGroups,
            in: context
        )
    }

    static func apply(
        _ delta: TabStructuralPersistenceDelta,
        in context: ModelContext
    ) throws {
        try TabSnapshotValidator.validateDelta(delta)

        let upsertSpaceIds = Set(delta.spaces.map(\.id))
        let deletedSpacesById = try TabStoreRecordQueries.spaces(
            in: context,
            ids: delta.deletedSpaceIds
        )
        for spaceId in delta.deletedSpaceIds {
            for tab in try TabStoreRecordQueries.tabs(in: context, spaceId: spaceId) {
                context.delete(tab)
            }
            for folder in try TabStoreRecordQueries.folders(in: context, spaceId: spaceId) {
                context.delete(folder)
            }
            if upsertSpaceIds.contains(spaceId) == false,
               let space = deletedSpacesById[spaceId] {
                context.delete(space)
            }
        }

        let upsertTabIds = Set(delta.tabs.map(\.id))
        let deletedTabIds = delta.deletedTabIds.subtracting(upsertTabIds)
        let deletedTabsById = try TabStoreRecordQueries.tabs(in: context, ids: deletedTabIds)
        for tabId in deletedTabIds {
            if let tab = deletedTabsById[tabId] {
                context.delete(tab)
            }
        }

        let upsertFolderIds = Set(delta.folders.map(\.id))
        let deletedFolderIds = delta.deletedFolderIds.subtracting(upsertFolderIds)
        let deletedFoldersById = try TabStoreRecordQueries.folders(
            in: context,
            ids: deletedFolderIds
        )
        for folderId in deletedFolderIds {
            if let folder = deletedFoldersById[folderId] {
                context.delete(folder)
            }
        }

        let existingSpacesById = try TabStoreRecordQueries.spaces(in: context, ids: upsertSpaceIds)
        for space in delta.spaces {
            TabStoreRecordMutation.upsert(space, existing: existingSpacesById[space.id], in: context)
        }

        let existingFoldersById = try TabStoreRecordQueries.folders(in: context, ids: upsertFolderIds)
        for folder in delta.folders {
            TabStoreRecordMutation.upsert(folder, existing: existingFoldersById[folder.id], in: context)
        }

        let existingTabsById = try TabStoreRecordQueries.tabs(in: context, ids: upsertTabIds)
        for tab in delta.tabs {
            TabStoreRecordMutation.upsert(tab, existing: existingTabsById[tab.id], in: context)
        }

        try TabStoreRecordMutation.upsertSelection(
            delta.state,
            splitGroups: delta.splitGroups,
            in: context
        )
    }
}

enum TabStoreIntegrityValidator {
    static func validate(in context: ModelContext) throws {
        let tabs = try context.fetch(FetchDescriptor<TabEntity>())
        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>())
        let spaceIds = Set(spaces.map(\.id))
        for tab in tabs {
            if let spaceId = tab.spaceId, spaceIds.contains(spaceId) == false {
                throw TabPersistenceError.dataCorruption
            }
        }
    }
}
