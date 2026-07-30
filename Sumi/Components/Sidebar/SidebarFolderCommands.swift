import Foundation

@MainActor
final class SidebarFolderCommands {
    private let identity: SidebarFolderIdentityQuery
    private let structure: SpacePinnedStructureOwner
    private let content: TabFolderContentMutationTransaction
    private let retirement: TabFolderRetirementTransaction
    private let openState: TabFolderOpenStateService

    init(
        runtime: TabRuntimePortConnection,
        folders: TabFolderCollectionStateOwner,
        structure: SpacePinnedStructureOwner,
        content: TabFolderContentMutationTransaction,
        retirement: TabFolderRetirementTransaction,
        openState: TabFolderOpenStateService
    ) {
        self.identity = SidebarFolderIdentityQuery(
            runtime: runtime,
            folders: folders
        )
        self.structure = structure
        self.content = content
        self.retirement = retirement
        self.openState = openState
    }

    func recursiveChildCount(for folderID: UUID, in spaceID: UUID) -> Int? {
        guard isCurrent(folderID, in: spaceID) else { return nil }
        return structure.folderRecursiveChildCount(for: folderID, in: spaceID)
    }

    func toggleFolder(_ folderID: UUID) -> Bool {
        guard isCurrent(folderID) else { return false }
        openState.toggleFolderOpenState(folderID)
        return true
    }

    func deleteFolder(_ folderID: UUID) -> Bool {
        guard isCurrent(folderID) else { return false }
        retirement.deleteFolder(folderID)
        return true
    }

    func ungroupFolder(_ folderID: UUID) -> Bool {
        guard isCurrent(folderID) else { return false }
        retirement.ungroupFolder(folderID)
        return true
    }

    func alphabetizeFolder(_ folderID: UUID, in spaceID: UUID) -> Bool {
        guard isCurrent(folderID, in: spaceID) else { return false }
        content.alphabetizeFolderPins(folderID, in: spaceID)
        return true
    }

    func createFolder(
        in spaceID: UUID,
        parentFolderID: UUID? = nil,
        name: String,
        isLiveFolder: Bool = false
    ) -> TabFolder? {
        guard identity.runtimeIsAvailable else { return nil }
        return content.createFolder(
            for: spaceID,
            parentFolderID: parentFolderID,
            name: name,
            isLiveFolder: isLiveFolder
        )
    }

    func markFolderLive(_ folderID: UUID) {
        guard isCurrent(folderID) else { return }
        content.markFolderLive(folderID)
    }

    func renameFolder(_ folderID: UUID, to name: String) {
        guard isCurrent(folderID) else { return }
        content.renameFolder(folderID, newName: name)
    }

    func updateFolderIcon(_ folderID: UUID, icon: String) {
        guard isCurrent(folderID) else { return }
        content.updateFolderIcon(folderID, icon: icon)
    }

    private func isCurrent(_ folderID: UUID, in spaceID: UUID? = nil) -> Bool {
        identity.isCurrent(folderID, in: spaceID)
    }
}

@MainActor
private final class SidebarFolderIdentityQuery {
    private let runtime: TabRuntimePortConnection
    private let folders: TabFolderCollectionStateOwner

    init(
        runtime: TabRuntimePortConnection,
        folders: TabFolderCollectionStateOwner
    ) {
        self.runtime = runtime
        self.folders = folders
    }

    var runtimeIsAvailable: Bool { runtime.current != nil }

    func isCurrent(_ folderID: UUID, in spaceID: UUID?) -> Bool {
        guard runtimeIsAvailable,
              let folder = folders.folder(by: folderID) else { return false }
        return spaceID.map { folder.spaceId == $0 } ?? true
    }
}
