import SwiftData

actor TabRestoreStoreReader {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func read() throws -> TabRestoreStoreRecords {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>()).map { entity in
            TabRestoreSpaceRecord(
                id: entity.id,
                name: entity.name,
                icon: entity.icon,
                index: entity.index,
                workspaceThemeData: entity.workspaceThemeData,
                profileId: entity.profileId
            )
        }
        let tabs = try context.fetch(FetchDescriptor<TabEntity>()).map { entity in
            TabRestoreTabRecord(
                id: entity.id,
                urlString: entity.urlString,
                name: entity.name,
                isPinned: entity.isPinned,
                isSpacePinned: entity.isSpacePinned,
                index: entity.index,
                spaceId: entity.spaceId,
                profileId: entity.profileId,
                executionProfileId: entity.executionProfileId,
                folderId: entity.folderId,
                iconAsset: entity.iconAsset,
                // Legacy launchers have no marker. Preserve their saved names
                // instead of risking a user-authored title being overwritten.
                titleIsCustom: entity.titleIsCustom ?? true,
                currentURLString: entity.currentURLString,
                canGoBack: entity.canGoBack,
                canGoForward: entity.canGoForward
            )
        }
        let folders = try context.fetch(FetchDescriptor<FolderEntity>()).map { entity in
            TabRestoreFolderRecord(
                id: entity.id,
                name: entity.name,
                icon: entity.icon,
                color: entity.color,
                spaceId: entity.spaceId,
                parentFolderId: entity.parentFolderId,
                isOpen: entity.isOpen,
                index: entity.index
            )
        }
        let states = try context.fetch(FetchDescriptor<TabsStateEntity>()).map { entity in
            TabRestoreStateRecord(
                currentTabID: entity.currentTabID,
                currentSpaceID: entity.currentSpaceID,
                splitGroupsData: entity.splitGroupsData
            )
        }
        return TabRestoreStoreRecords(
            spaces: spaces,
            tabs: tabs,
            folders: folders,
            states: states
        )
    }
}
