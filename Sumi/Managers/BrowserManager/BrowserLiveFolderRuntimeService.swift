import Foundation

@MainActor
enum BrowserLiveFolderRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> SumiLiveFolderRuntime {
        SumiLiveFolderRuntime(
            spaceContext: { [weak browserManager] spaceId in
                guard let space = browserManager?.tabManager.spaces.first(where: { $0.id == spaceId }) else {
                    return nil
                }
                return SumiLiveFolderRuntime.SpaceContext(profileId: space.profileId)
            },
            createFolder: { [weak browserManager] spaceId, name in
                browserManager?.tabManager.createFolder(for: spaceId, name: name).id
            },
            updateFolderIcon: { [weak browserManager] folderId, icon in
                browserManager?.tabManager.updateFolderIcon(folderId, icon: icon)
            },
            renameFolder: { [weak browserManager] folderId, name in
                browserManager?.tabManager.renameFolder(folderId, newName: name)
            },
            openNewTab: { [weak browserManager] urlString, windowState, preferredSpaceId in
                browserManager?.openNewTab(
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
                if let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }),
                   let profileId = space.profileId {
                    return browserManager.profileManager.profiles.first { $0.id == profileId }
                }
                return browserManager.currentProfile
            },
            folderIds: { [weak browserManager] in
                guard let browserManager else { return nil }
                return Set(
                    browserManager.tabManager.foldersBySpace.values.flatMap { folders in
                        folders.map(\.id)
                    }
                )
            }
        )
    }
}
