import Foundation

@MainActor
enum BrowserLiveFolderRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> SumiLiveFolderRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return SumiLiveFolderRuntime(
            spaceContext: { [weak browserManager] spaceId in
                guard let space = browserManager?.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId }) else {
                    return nil
                }
                return SumiLiveFolderRuntime.SpaceContext(profileId: space.profileId)
            },
            createFolder: { [weak browserManager] spaceId, name in
                browserManager?.tabManager.folderMutationOwner.createFolder(for: spaceId, name: name).id
            },
            updateFolderIcon: { [weak browserManager] folderId, icon in
                browserManager?.tabManager.folderMutationOwner.updateFolderIcon(folderId, icon: icon)
            },
            renameFolder: { [weak browserManager] folderId, name in
                browserManager?.tabManager.folderMutationOwner.renameFolder(folderId, newName: name)
            },
            openNewTab: { [weak browserManager] urlString, windowState, preferredSpaceId in
                browserManager?.tabLifecycleService.opening.openNewTab(
                    url: urlString,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            profile: { [weak browserManager] profileId, spaceId in
                guard let browserManager else { return nil }
                if let profileId,
                   let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
                    return profile
                }
                if let space = browserManager.tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId }),
                   let profileId = space.profileId {
                    return browserManager.profileManager.profiles.first { $0.id == profileId }
                }
                return currentProfileAuthority.currentProfile
            },
            folderIds: { [weak browserManager] in
                guard let browserManager else { return [] }
                return Set(
                    browserManager.tabManager.folderCollectionStateOwner.allFolders().map(\.id)
                )
            }
        )
    }
}
