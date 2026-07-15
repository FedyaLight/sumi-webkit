import SwiftData
import SumiDomain

enum TabStoreRecordMutation {
    static func upsert(
        _ tab: TabPersistenceTab,
        existing: TabEntity?,
        in context: ModelContext
    ) {
        guard let existing else {
            context.insert(
                TabEntity(
                    id: tab.id,
                    urlString: tab.urlString,
                    name: tab.name,
                    isPinned: tab.isPinned,
                    isSpacePinned: tab.isSpacePinned,
                    index: tab.index,
                    spaceId: tab.spaceId,
                    profileId: tab.profileId,
                    executionProfileId: tab.executionProfileId,
                    folderId: tab.folderId,
                    iconAsset: tab.iconAsset,
                    currentURLString: tab.currentURLString,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                )
            )
            return
        }

        existing.urlString = tab.urlString
        existing.name = tab.name
        existing.isPinned = tab.isPinned
        existing.isSpacePinned = tab.isSpacePinned
        existing.index = tab.index
        existing.spaceId = tab.spaceId
        existing.profileId = tab.profileId
        existing.executionProfileId = tab.executionProfileId
        existing.folderId = tab.folderId
        existing.iconAsset = tab.iconAsset
        existing.currentURLString = tab.currentURLString
        existing.canGoBack = tab.canGoBack
        existing.canGoForward = tab.canGoForward
    }

    static func apply(_ update: TabRuntimeStateUpdate, to tab: TabEntity) {
        tab.urlString = update.urlString
        tab.currentURLString = update.currentURLString
        tab.name = update.name
        tab.canGoBack = update.canGoBack
        tab.canGoForward = update.canGoForward
    }

    static func upsert(
        _ folder: TabPersistenceFolder,
        existing: FolderEntity?,
        in context: ModelContext
    ) {
        let icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon)
        guard let existing else {
            context.insert(
                FolderEntity(
                    id: folder.id,
                    name: folder.name,
                    icon: icon,
                    color: folder.color,
                    spaceId: folder.spaceId,
                    parentFolderId: folder.parentFolderId,
                    isOpen: folder.isOpen,
                    index: folder.index
                )
            )
            return
        }

        existing.name = folder.name
        existing.icon = icon
        existing.color = folder.color
        existing.spaceId = folder.spaceId
        existing.parentFolderId = folder.parentFolderId
        existing.index = folder.index
        existing.isOpen = folder.isOpen
    }

    static func upsert(
        _ space: TabPersistenceSpace,
        existing: SpaceEntity?,
        in context: ModelContext
    ) {
        guard let existing else {
            context.insert(
                SpaceEntity(
                    id: space.id,
                    name: space.name,
                    icon: space.icon,
                    index: space.index,
                    workspaceThemeData: space.workspaceThemeData,
                    profileId: space.profileId
                )
            )
            return
        }

        existing.name = space.name
        existing.icon = space.icon
        existing.index = space.index
        existing.workspaceThemeData = space.workspaceThemeData
        existing.profileId = space.profileId
    }

    static func upsertSelection(
        _ selection: TabPersistenceSelection,
        splitGroups: [SplitGroup]? = nil,
        in context: ModelContext,
        codec: TabPersistenceCodec = TabPersistenceCodec()
    ) throws {
        let states = try context.fetch(FetchDescriptor<TabsStateEntity>())
        let state = states.first ?? {
            let state = TabsStateEntity(currentTabID: nil, currentSpaceID: nil)
            context.insert(state)
            return state
        }()
        state.currentTabID = selection.currentTabID
        state.currentSpaceID = selection.currentSpaceID
        if let splitGroups {
            state.splitGroupsData = try codec.encodeSplitGroups(splitGroups)
        }

        for duplicate in states.dropFirst() {
            context.delete(duplicate)
        }
    }
}
