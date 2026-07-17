import Foundation

@MainActor
enum BrowserLiveFolderRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> SumiLiveFolderRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let spaces = browserManager.spaceStateOwner
        let folderCommands = browserManager.sidebarFolderCommands
        let folderState = browserManager.folderCollectionStateOwner
        let profiles = browserManager.profileManager
        return SumiLiveFolderRuntime(
            spaceContext: { [spaces] spaceId in
                guard let space = spaces.space(with: spaceId) else {
                    return nil
                }
                return SumiLiveFolderRuntime.SpaceContext(profileId: space.profileId)
            },
            createFolder: { [folderCommands] spaceId, name in
                folderCommands.createFolder(in: spaceId, name: name)?.id
            },
            updateFolderIcon: { [folderCommands] folderId, icon in
                folderCommands.updateFolderIcon(folderId, icon: icon)
            },
            renameFolder: { [folderCommands] folderId, name in
                folderCommands.renameFolder(folderId, to: name)
            },
            openNewTab: { [weak browserManager] urlString, windowState, preferredSpaceId in
                browserManager?.tabOpening.openNewTab(
                    url: urlString,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            profile: { [profiles, spaces] profileId, spaceId in
                if let profileId,
                   let profile = profiles.profiles.first(where: { $0.id == profileId }) {
                    return profile
                }
                if let space = spaces.space(with: spaceId),
                   let profileId = space.profileId {
                    return profiles.profiles.first { $0.id == profileId }
                }
                return currentProfileAuthority.currentProfile
            },
            folderIds: { [folderState] in
                Set(folderState.allFolders().map(\.id))
            }
        )
    }
}
