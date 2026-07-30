actor TabRestoreStoreReader {
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func read() throws -> TabRestoreStoreRecords {
        try database.read { connection in
            let spaces = try connection.workspace.spaces().map { record in
                TabRestoreSpaceRecord(
                    id: record.id,
                    name: record.name,
                    icon: record.icon,
                    index: record.index,
                    workspaceThemeData: record.workspaceThemeData,
                    profileId: record.profileID
                )
            }
            let tabs = try connection.workspace.tabs().map { record in
                TabRestoreTabRecord(
                    id: record.id,
                    urlString: record.urlString,
                    name: record.name,
                    isPinned: record.isPinned,
                    isSpacePinned: record.isSpacePinned,
                    index: record.index,
                    spaceId: record.spaceID,
                    profileId: record.profileID,
                    executionProfileId: record.executionProfileID,
                    folderId: record.folderID,
                    iconAsset: record.iconAsset,
                    titleIsCustom: record.titleIsCustom,
                    currentURLString: record.currentURLString,
                    canGoBack: record.canGoBack,
                    canGoForward: record.canGoForward
                )
            }
            let folders = try connection.workspace.folders().map { record in
                TabRestoreFolderRecord(
                    id: record.id,
                    name: record.name,
                    icon: record.icon,
                    color: record.color,
                    spaceId: record.spaceID,
                    parentFolderId: record.parentFolderID,
                    isOpen: record.isOpen,
                    isLiveFolder: record.isLiveFolder,
                    index: record.index
                )
            }
            let states = try connection.workspace.state().map { record in
                [
                    TabRestoreStateRecord(
                        currentTabID: record.currentTabID,
                        currentSpaceID: record.currentSpaceID,
                        splitGroupsData: record.splitGroupsData
                    ),
                ]
            } ?? []
            return TabRestoreStoreRecords(
                spaces: spaces,
                tabs: tabs,
                folders: folders,
                states: states
            )
        }
    }
}
