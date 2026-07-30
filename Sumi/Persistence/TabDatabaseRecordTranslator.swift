import Foundation
import SumiDomain

enum TabDatabaseRecordTranslator {
    static func space(_ source: TabPersistenceSpace) throws -> SpaceRecord {
        guard let profileID = source.profileId else {
            throw TabPersistenceError.invalidModelState
        }
        return SpaceRecord(
            id: source.id,
            profileID: profileID,
            name: source.name,
            icon: source.icon,
            index: source.index,
            workspaceThemeData: source.workspaceThemeData
        )
    }

    static func folder(_ source: TabPersistenceFolder) -> FolderRecord {
        FolderRecord(
            id: source.id,
            spaceID: source.spaceId,
            parentFolderID: source.parentFolderId,
            name: source.name,
            icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(source.icon),
            color: source.color,
            isOpen: source.isOpen,
            isLiveFolder: source.isLiveFolder,
            index: source.index
        )
    }

    static func tab(_ source: TabPersistenceTab) throws -> TabRecord {
        TabRecord(
            id: source.id,
            profileID: source.profileId,
            executionProfileID: source.executionProfileId,
            spaceID: source.spaceId,
            folderID: source.folderId,
            urlString: source.urlString,
            name: source.name,
            isPinned: source.isPinned,
            isSpacePinned: source.isSpacePinned,
            index: source.index,
            iconAsset: source.iconAsset,
            titleIsCustom: source.titleIsCustom,
            currentURLString: source.currentURLString ?? source.urlString,
            canGoBack: source.canGoBack,
            canGoForward: source.canGoForward
        )
    }

    static func state(
        _ selection: TabPersistenceSelection,
        splitGroups: [SplitGroup]?,
        existing: TabStateRecord?,
        codec: TabPersistenceCodec = TabPersistenceCodec()
    ) throws -> TabStateRecord {
        TabStateRecord(
            currentTabID: selection.currentTabID,
            currentSpaceID: selection.currentSpaceID,
            splitGroupsData: try splitGroups.map(codec.encodeSplitGroups)
                ?? existing?.splitGroupsData
        )
    }
}
