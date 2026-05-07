import Bookmarks
import CoreData
import Foundation

@MainActor
final class SumiDDGBookmarkRepository: SumiBookmarkRepository, @unchecked Sendable {
    private let context: NSManagedObjectContext

    init(database: SumiBookmarkDatabase) {
        context = database.makeContext(
            concurrencyType: .mainQueueConcurrencyType,
            name: "SumiBookmarksMain"
        )
    }

    func fetchBookmarks() -> [SumiBookmark] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == NO AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(BookmarkEntity.modifiedAt), ascending: true),
            NSSortDescriptor(key: #keyPath(BookmarkEntity.title), ascending: true),
        ]
        request.returnsObjectsAsFaults = false

        let entities = (try? context.fetch(request)) ?? []
        return entities.compactMap(bookmark(from:))
    }

    func snapshot(sortMode: SumiBookmarkSortMode = .manual) -> SumiBookmarksSnapshot {
        guard let root = rootFolder(),
              let rootNode = makeSnapshotNode(
                from: root,
                depth: 0,
                sortMode: sortMode,
                entitiesByID: nil,
                flattenedFolders: nil
              )
        else {
            let root = SumiBookmarkEntity(
                id: BookmarkEntity.Constants.rootFolderID,
                kind: .folder,
                title: "Bookmarks",
                url: nil,
                parentID: nil,
                parentTitle: nil,
                children: [],
                childBookmarkCount: 0
            )
            return SumiBookmarksSnapshot(
                root: root,
                flattenedFolders: [.init(id: root.id, title: root.title, depth: 0)],
                entitiesByID: [root.id: root]
            )
        }

        var entitiesByID: [String: SumiBookmarkEntity] = [:]
        var flattenedFolders: [SumiBookmarkFolder] = []
        guard let populatedRoot = makeSnapshotNode(
            from: root,
            depth: 0,
            sortMode: sortMode,
            entitiesByID: &entitiesByID,
            flattenedFolders: &flattenedFolders
        ) else {
            return SumiBookmarksSnapshot(
                root: rootNode,
                flattenedFolders: [.init(id: rootNode.id, title: rootNode.title, depth: 0)],
                entitiesByID: [rootNode.id: rootNode]
            )
        }

        return SumiBookmarksSnapshot(
            root: populatedRoot,
            flattenedFolders: flattenedFolders,
            entitiesByID: entitiesByID
        )
    }

    func entity(id: String, sortMode: SumiBookmarkSortMode = .manual) -> SumiBookmarkEntity? {
        snapshot(sortMode: sortMode).entitiesByID[id]
    }

    func openableURLs(for ids: [String]) -> [URL] {
        var urls: [URL] = []
        for id in ids {
            guard let entity = entityForAnyID(id) else { continue }
            urls.append(contentsOf: openableURLs(from: entity))
        }
        return uniqueURLsPreservingOrder(urls)
    }

    @discardableResult
    func createBookmark(
        url: URL,
        title: String,
        folderID: String?
    ) throws -> SumiBookmark {
        guard let parent = folderEntity(for: folderID) ?? rootFolder() else {
            throw SumiBookmarkError.missingRootFolder
        }

        let entity = BookmarkEntity.makeBookmark(
            title: title,
            url: url.absoluteString,
            parent: parent,
            context: context
        )
        try save()
        guard let id = entity.uuid,
              let bookmark = bookmarkEntity(id: id).flatMap(bookmark(from:))
        else {
            throw SumiBookmarkError.missingBookmark
        }
        return bookmark
    }

    @discardableResult
    func updateBookmark(
        id: String,
        title: String,
        url: URL,
        folderID: String?
    ) throws -> SumiBookmark {
        guard let entity = bookmarkEntity(id: id) else {
            throw SumiBookmarkError.missingBookmark
        }

        entity.title = title
        entity.url = url.absoluteString

        let targetParent = try requiredFolderEntity(for: folderID)
        if entity.parent?.uuid != targetParent.uuid {
            entity.parent?.removeFromChildren(entity)
            targetParent.addToChildren(entity)
        }

        try save()
        guard let bookmark = bookmarkEntity(id: id).flatMap(bookmark(from:)) else {
            throw SumiBookmarkError.missingBookmark
        }
        return bookmark
    }

    @discardableResult
    func createFolder(title: String, parentID: String?) throws -> SumiBookmarkEntity {
        guard let parent = folderEntity(for: parentID) ?? rootFolder() else {
            throw SumiBookmarkError.missingRootFolder
        }

        let folder = BookmarkEntity.makeFolder(
            title: title,
            parent: parent,
            context: context
        )
        try save()
        guard let id = folder.uuid,
              let node = entity(id: id)
        else {
            throw SumiBookmarkError.missingFolder
        }
        return node
    }

    @discardableResult
    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity {
        guard id != BookmarkEntity.Constants.rootFolderID else {
            throw SumiBookmarkError.cannotDeleteRootFolder
        }
        guard let folder = folderEntity(for: id), folder.isRoot == false else {
            throw SumiBookmarkError.missingFolder
        }
        let targetParent = try requiredFolderEntity(for: parentID)
        if isDescendant(targetParent, of: folder) || targetParent == folder {
            throw SumiBookmarkError.cannotMoveFolderIntoDescendant
        }

        folder.title = title
        if folder.parent?.uuid != targetParent.uuid {
            folder.parent?.removeFromChildren(folder)
            targetParent.addToChildren(folder)
        }

        try save()
        guard let node = entity(id: id) else { throw SumiBookmarkError.missingFolder }
        return node
    }

    func removeEntities(ids: [String]) throws {
        var entitiesToDelete: [BookmarkEntity] = []
        for id in ids {
            guard id != BookmarkEntity.Constants.rootFolderID else {
                throw SumiBookmarkError.cannotDeleteRootFolder
            }
            guard let entity = entityForAnyID(id) else {
                throw SumiBookmarkError.missingBookmark
            }
            entitiesToDelete.append(entity)
        }

        for entity in entitiesToDelete {
            entity.parent?.removeFromChildren(entity)
            deleteRecursively(entity)
        }
        try save()
    }

    func moveEntities(
        ids: [String],
        toParentID parentID: String?,
        atIndex index: Int? = nil
    ) throws {
        guard !ids.isEmpty else { return }
        let targetParent = try requiredFolderEntity(for: parentID)
        let moving = ids.compactMap(entityForAnyID)
        guard moving.count == ids.count else { throw SumiBookmarkError.missingBookmark }

        for entity in moving {
            guard entity.uuid != BookmarkEntity.Constants.rootFolderID else {
                throw SumiBookmarkError.cannotDeleteRootFolder
            }
            if entity.isFolder,
               (entity == targetParent || isDescendant(targetParent, of: entity)) {
                throw SumiBookmarkError.cannotMoveFolderIntoDescendant
            }
        }

        for entity in moving {
            entity.parent?.removeFromChildren(entity)
        }

        if let index {
            var targetIndex = max(0, min(index, targetParent.childrenArray.count))
            for entity in moving {
                targetParent.insertIntoChildren(entity, at: targetIndex)
                targetIndex += 1
            }
        } else {
            for entity in moving {
                targetParent.addToChildren(entity)
            }
        }

        try save()
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String?,
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        let parent = try requiredFolderEntity(for: parentID)
        let importer = BookmarkCoreDataImporter(
            context: context,
            acceptsURL: acceptsURL,
            urlKeys: urlKeys
        )
        let summary = try importer.importBookmarks(
            bookmarks.map(\.ddgBookmarkOrFolder),
            parent: parent
        )
        return SumiBookmarksImportSummary(ddgImportSummary: summary)
    }

    func exportBookmarksHTML(to destination: URL) throws {
        try BookmarkHTMLExporter.exportBookmarksHTML(from: context, to: destination)
    }

    nonisolated func mergeChanges(fromContextDidSave notification: Notification) -> Bool {
        guard let savingContext = notification.object as? NSManagedObjectContext,
              savingContext !== context,
              savingContext.persistentStoreCoordinator === context.persistentStoreCoordinator
        else {
            return false
        }
        context.mergeChanges(fromContextDidSave: notification)
        return true
    }

    private func bookmark(from entity: BookmarkEntity) -> SumiBookmark? {
        guard let id = entity.uuid,
              let urlString = entity.url,
              let url = URL(string: urlString)
        else {
            return nil
        }

        let title = entity.title?.nilIfTrimmedEmpty
            ?? url.sumiSuggestedTitlePlaceholder
            ?? url.absoluteString
        let folderID = entity.parent?.uuid

        return SumiBookmark(
            id: id,
            title: title,
            url: url,
            folderID: folderID
        )
    }

    private func makeSnapshotNode(
        from entity: BookmarkEntity,
        depth: Int,
        sortMode: SumiBookmarkSortMode,
        entitiesByID: UnsafeMutablePointer<[String: SumiBookmarkEntity]>?,
        flattenedFolders: UnsafeMutablePointer<[SumiBookmarkFolder]>?
    ) -> SumiBookmarkEntity? {
        guard let id = entity.uuid else { return nil }

        if entity.isFolder {
            let title = displayTitle(forFolder: entity) ?? sanitizedFolderTitle(entity.title ?? "")
            flattenedFolders?.pointee.append(.init(id: id, title: title, depth: depth))
            let childNodes = sortedChildren(entity.childrenArray, sortMode: sortMode)
                .compactMap {
                    makeSnapshotNode(
                        from: $0,
                        depth: depth + 1,
                        sortMode: sortMode,
                        entitiesByID: entitiesByID,
                        flattenedFolders: flattenedFolders
                    )
                }
            let count = childNodes.reduce(0) { result, child in
                result + (child.isBookmark ? 1 : child.childBookmarkCount)
            }
            let node = SumiBookmarkEntity(
                id: id,
                kind: .folder,
                title: title,
                url: nil,
                parentID: entity.parent?.uuid,
                parentTitle: displayTitle(forFolder: entity.parent),
                children: childNodes,
                childBookmarkCount: count
            )
            entitiesByID?.pointee[id] = node
            return node
        }

        guard let urlString = entity.url,
              let url = URL(string: urlString)
        else {
            return nil
        }
        let title = entity.title?.nilIfTrimmedEmpty
            ?? url.sumiSuggestedTitlePlaceholder
            ?? url.absoluteString
        let node = SumiBookmarkEntity(
            id: id,
            kind: .bookmark,
            title: title,
            url: url,
            parentID: entity.parent?.uuid,
            parentTitle: displayTitle(forFolder: entity.parent),
            children: [],
            childBookmarkCount: 0
        )
        entitiesByID?.pointee[id] = node
        return node
    }

    private func sortedChildren(
        _ children: [BookmarkEntity],
        sortMode: SumiBookmarkSortMode
    ) -> [BookmarkEntity] {
        switch sortMode {
        case .manual:
            return children
        case .nameAscending:
            return children.sorted { lhs, rhs in
                Self.compareEntities(lhs, rhs, ascending: true)
            }
        case .nameDescending:
            return children.sorted { lhs, rhs in
                Self.compareEntities(lhs, rhs, ascending: false)
            }
        }
    }

    private func bookmarkEntity(id: String) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == NO AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.uuid), id,
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        return try? context.fetch(request).first
    }

    private func entityForAnyID(_ id: String) -> BookmarkEntity? {
        if id == BookmarkEntity.Constants.rootFolderID {
            return rootFolder()
        }
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.uuid), id,
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        return try? context.fetch(request).first
    }

    private func rootFolder() -> BookmarkEntity? {
        BookmarkUtils.fetchRootFolder(context)
    }

    private func requiredFolderEntity(for id: String?) throws -> BookmarkEntity {
        if let folder = folderEntity(for: id) {
            return folder
        }
        throw id == nil ? SumiBookmarkError.missingRootFolder : SumiBookmarkError.missingFolder
    }

    private func folderEntity(for id: String?) -> BookmarkEntity? {
        guard let id,
              id != BookmarkEntity.Constants.rootFolderID
        else {
            return rootFolder()
        }

        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == YES AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.uuid), id,
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        return try? context.fetch(request).first
    }

    private func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw SumiBookmarkError.saveFailed(error.localizedDescription)
        }
    }

    private func sanitizedFolderTitle(_ title: String) -> String {
        title.nilIfTrimmedEmpty ?? "Folder"
    }

    private func displayTitle(forFolder folder: BookmarkEntity?) -> String? {
        guard let folder else { return nil }
        if folder.uuid == BookmarkEntity.Constants.rootFolderID {
            return "Bookmarks"
        }
        return folder.title?.nilIfTrimmedEmpty
    }

    private func isDescendant(_ possibleDescendant: BookmarkEntity, of ancestor: BookmarkEntity) -> Bool {
        var current = possibleDescendant.parent
        while let folder = current {
            if folder == ancestor {
                return true
            }
            current = folder.parent
        }
        return false
    }

    private func deleteRecursively(_ entity: BookmarkEntity) {
        if entity.isFolder {
            for child in entity.childrenArray {
                deleteRecursively(child)
            }
        }
        context.delete(entity)
    }

    private func openableURLs(from entity: BookmarkEntity) -> [URL] {
        if entity.isFolder {
            return entity.childrenArray.flatMap(openableURLs(from:))
        }
        guard let urlString = entity.url,
              let url = URL(string: urlString)
        else {
            return []
        }
        return [url]
    }

    private func uniqueURLsPreservingOrder(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private static func compareEntities(
        _ lhs: BookmarkEntity,
        _ rhs: BookmarkEntity,
        ascending: Bool
    ) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        return compareTitles(lhs.title ?? "", rhs.title ?? "", ascending: ascending)
    }

    private static func compareTitles(_ lhs: String, _ rhs: String, ascending: Bool) -> Bool {
        let result = lhs.localizedCaseInsensitiveCompare(rhs)
        if result == .orderedSame {
            return ascending ? lhs < rhs : lhs > rhs
        }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
