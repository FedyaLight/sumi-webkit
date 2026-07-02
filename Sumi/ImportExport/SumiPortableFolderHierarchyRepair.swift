enum SumiPortableFolderHierarchyRepair {
    static func repaired(_ folders: [SumiPortableFolder]) -> [SumiPortableFolder] {
        let folderById = Dictionary(
            folders.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return folders.map { folder in
            var copy = folder
            guard let parentId = folder.parentFolderId else {
                return copy
            }
            guard parentId != folder.id,
                  let parent = folderById[parentId],
                  parent.spaceId == folder.spaceId,
                  createsCycle(folderId: folder.id, parentId: parentId, folderById: folderById) == false else {
                copy.parentFolderId = nil
                return copy
            }
            return copy
        }
    }

    private static func createsCycle(
        folderId: String,
        parentId: String,
        folderById: [String: SumiPortableFolder]
    ) -> Bool {
        var visited: Set<String> = [folderId]
        var cursor: String? = parentId
        while let current = cursor {
            guard visited.insert(current).inserted else { return true }
            cursor = folderById[current]?.parentFolderId
        }
        return false
    }
}
