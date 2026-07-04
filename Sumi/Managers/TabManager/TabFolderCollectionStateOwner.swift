import Foundation

@MainActor
final class TabFolderCollectionStateOwner {
    private(set) var foldersBySpace: [UUID: [TabFolder]] = [:]

    func replaceFoldersBySpace(_ foldersBySpace: [UUID: [TabFolder]]) {
        self.foldersBySpace = foldersBySpace
    }

    func foldersBySpaceSnapshot() -> [UUID: [TabFolder]] {
        foldersBySpace
    }

    func allFolders() -> [TabFolder] {
        foldersBySpace.values.flatMap { sortedFolders($0) }
    }

    func removeFolders(for spaceId: UUID) {
        foldersBySpace.removeValue(forKey: spaceId)
    }

    func removeAll() {
        foldersBySpace.removeAll()
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        sortedFolders(foldersBySpace[spaceId] ?? [])
    }

    func childFolders(of parentFolderId: UUID?, in spaceId: UUID) -> [TabFolder] {
        sortedFolders(
            (foldersBySpace[spaceId] ?? [])
                .filter { $0.parentFolderId == parentFolderId }
        )
    }

    func folder(by id: UUID) -> TabFolder? {
        for folders in foldersBySpace.values {
            if let match = folders.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    func spaceId(for folderId: UUID) -> UUID? {
        foldersBySpace.first { _, folders in
            folders.contains { $0.id == folderId }
        }?.key
    }

    func hasFolders(in spaceId: UUID) -> Bool {
        foldersBySpace[spaceId]?.isEmpty == false
    }

    private func sortedFolders(_ folders: [TabFolder]) -> [TabFolder] {
        folders.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
