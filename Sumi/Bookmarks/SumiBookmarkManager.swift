import Bookmarks
import CoreData
import Foundation

@MainActor
final class SumiBookmarkManager: ObservableObject {
    @Published private(set) var revision: UInt = 0

    private let database: SumiBookmarkDatabase
    private let context: NSManagedObjectContext
    private let syncFavicons: Bool
    private var bookmarksByID: [String: SumiBookmark] = [:]
    private var bookmarkIDByURLKey: [String: String] = [:]
    private var foldersCache: [SumiBookmarkFolder] = []
    private var didInstallSaveObserver = false
    private var saveObserver: NSObjectProtocol?

    init(
        database: SumiBookmarkDatabase = SumiBookmarkDatabase(),
        syncFavicons: Bool = true
    ) {
        self.database = database
        self.syncFavicons = syncFavicons
        context = database.makeContext(
            concurrencyType: .mainQueueConcurrencyType,
            name: "SumiBookmarksMain"
        )
        reload(notify: false)
        installSaveObserver()
    }

    deinit {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    func canBookmark(_ tab: Tab?) -> Bool {
        guard let tab,
              !tab.isEphemeral,
              !tab.representsSumiEmptySurface,
              !tab.representsSumiInternalSurface
        else {
            return false
        }
        return Self.canBookmark(tab.url)
    }

    static func canBookmark(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return url.host?.isEmpty == false
    }

    func isBookmarked(_ url: URL) -> Bool {
        bookmark(for: url) != nil
    }

    func bookmark(for url: URL) -> SumiBookmark? {
        for variant in url.sumiBookmarkButtonURLVariants() {
            let key = Self.urlKey(variant)
            if let id = bookmarkIDByURLKey[key],
               let bookmark = bookmarksByID[id]
            {
                return bookmark
            }
        }
        return nil
    }

    func folders() -> [SumiBookmarkFolder] {
        foldersCache
    }

    func bookmarks() -> [SumiBookmark] {
        bookmarksByID.values.sorted { lhs, rhs in
            Self.compareTitles(lhs.title, rhs.title, ascending: true)
        }
    }

    func allHosts() -> Set<String> {
        Set(bookmarksByID.values.compactMap { $0.url.host?.lowercased() })
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
                depth: 0,
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

    func visibleEntities(
        in folderID: String?,
        query: String,
        sortMode: SumiBookmarkSortMode
    ) -> [SumiBookmarkEntity] {
        let snapshot = snapshot(sortMode: sortMode)
        let folder = folderID.flatMap { snapshot.entitiesByID[$0] } ?? snapshot.root
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return folder.children
        }

        return flattenedDescendants(of: folder).filter { $0.matchesSearch(trimmedQuery) }
    }

    func entity(id: String, sortMode: SumiBookmarkSortMode = .manual) -> SumiBookmarkEntity? {
        snapshot(sortMode: sortMode).entitiesByID[id]
    }

    func openableURLs(for ids: some Sequence<String>) -> [URL] {
        var urls: [URL] = []
        for id in ids {
            guard let entity = entityForAnyID(id) else { continue }
            urls.append(contentsOf: openableURLs(from: entity))
        }
        return uniqueURLsPreservingOrder(urls)
    }

    func editorState(for tab: Tab) throws -> SumiBookmarkEditorState {
        guard canBookmark(tab) else { throw SumiBookmarkError.unsupportedURL }

        if let bookmark = bookmark(for: tab.url) {
            return SumiBookmarkEditorState(
                mode: .edit,
                bookmarkID: bookmark.id,
                tabID: tab.id,
                pageURL: tab.url,
                title: bookmark.title,
                urlString: bookmark.url.absoluteString,
                folderID: bookmark.folderID
            )
        }

        return SumiBookmarkEditorState(
            mode: .add,
            bookmarkID: nil,
            tabID: tab.id,
            pageURL: tab.url,
            title: suggestedTitle(for: tab),
            urlString: tab.url.absoluteString,
            folderID: nil
        )
    }

    @discardableResult
    func createBookmark(
        url: URL,
        title: String,
        folderID: String? = nil
    ) throws -> SumiBookmark {
        guard Self.canBookmark(url) else { throw SumiBookmarkError.unsupportedURL }
        if let existing = bookmark(for: url) {
            return existing
        }

        let title = sanitizedTitle(title, fallbackURL: url)
        guard let parent = folderEntity(for: folderID) ?? rootFolder() else {
            throw SumiBookmarkError.missingRootFolder
        }

        let entity = BookmarkEntity.makeBookmark(
            title: title,
            url: url.absoluteString,
            parent: parent,
            context: context
        )
        try saveAndReload()
        guard let id = entity.uuid,
              let bookmark = bookmarksByID[id]
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
        guard Self.canBookmark(url) else { throw SumiBookmarkError.unsupportedURL }
        let title = sanitizedTitle(title, fallbackURL: url)
        guard let entity = bookmarkEntity(id: id) else {
            throw SumiBookmarkError.missingBookmark
        }

        if let duplicate = bookmark(for: url),
           duplicate.id != id
        {
            throw SumiBookmarkError.duplicateURL
        }

        entity.title = title
        entity.url = url.absoluteString

        let targetParent = try requiredFolderEntity(for: folderID)
        if entity.parent?.uuid != targetParent.uuid {
            entity.parent?.removeFromChildren(entity)
            targetParent.addToChildren(entity)
        }

        try saveAndReload()
        guard let bookmark = bookmarksByID[id] else {
            throw SumiBookmarkError.missingBookmark
        }
        return bookmark
    }

    @discardableResult
    func createFolder(title: String, parentID: String? = nil) throws -> SumiBookmarkEntity {
        let title = sanitizedFolderTitle(title)
        guard let parent = folderEntity(for: parentID) ?? rootFolder() else {
            throw SumiBookmarkError.missingRootFolder
        }

        let folder = BookmarkEntity.makeFolder(
            title: title,
            parent: parent,
            context: context
        )
        try saveAndReload()
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

        folder.title = sanitizedFolderTitle(title)
        if folder.parent?.uuid != targetParent.uuid {
            folder.parent?.removeFromChildren(folder)
            targetParent.addToChildren(folder)
        }

        try saveAndReload()
        guard let node = entity(id: id) else { throw SumiBookmarkError.missingFolder }
        return node
    }

    func removeBookmark(id: String) throws {
        try removeEntities(ids: [id])
    }

    func removeEntities(ids: some Sequence<String>) throws {
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
        try saveAndReload()
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

        try saveAndReload()
    }

    func importBookmarks(
        _ nodes: [SumiImportedBookmarkNode],
        sourceName: String,
        parentID: String? = nil
    ) throws -> SumiBookmarkImportSummary {
        let parent = try requiredFolderEntity(for: parentID)
        var summary = SumiBookmarkImportSummary(
            sourceName: sourceName,
            imported: 0,
            duplicates: 0,
            failed: 0
        )
        var knownURLKeys = Set(bookmarkIDByURLKey.keys)

        for node in nodes {
            importNode(
                node,
                into: parent,
                knownURLKeys: &knownURLKeys,
                summary: &summary
            )
        }

        try saveAndReload()
        return summary
    }

    func exportBookmarksHTML() throws -> String {
        guard let root = rootFolder() else {
            throw SumiBookmarkError.exportFailed("Bookmarks storage is not ready.")
        }

        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]
        appendExportLines(for: root.childrenArray, indent: 1, to: &lines)
        lines.append("</DL><p>")
        return lines.joined(separator: "\n")
    }

    func exportBookmarksHTML(to destination: URL) throws {
        do {
            try exportBookmarksHTML().write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw SumiBookmarkError.exportFailed(error.localizedDescription)
        }
    }

    private func installSaveObserver() {
        guard !didInstallSaveObserver else { return }
        didInstallSaveObserver = true
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let savingContext = notification.object as? NSManagedObjectContext,
                      savingContext !== self.context,
                      savingContext.persistentStoreCoordinator === self.context.persistentStoreCoordinator
                else {
                    return
                }
                self.context.mergeChanges(fromContextDidSave: notification)
                self.reload()
            }
        }
    }

    private func reload(notify: Bool = true) {
        let bookmarks = fetchBookmarks()
        bookmarksByID = Dictionary(
            uniqueKeysWithValues: bookmarks.map { ($0.id, $0) }
        )
        var urlIndex: [String: String] = [:]
        for bookmark in bookmarks {
            for variant in bookmark.url.sumiBookmarkButtonURLVariants() {
                urlIndex[Self.urlKey(variant), default: bookmark.id] = bookmark.id
            }
        }
        bookmarkIDByURLKey = urlIndex
        foldersCache = fetchFolders()

        if syncFavicons {
            SumiFaviconSystem.shared.syncBookmarks(bookmarks)
        }

        if notify {
            revision &+= 1
        }
    }

    private func fetchBookmarks() -> [SumiBookmark] {
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

    private func fetchFolders() -> [SumiBookmarkFolder] {
        snapshot(sortMode: .manual).flattenedFolders
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
        let folderTitle = displayTitle(forFolder: entity.parent)

        return SumiBookmark(
            id: id,
            title: title,
            url: url,
            folderID: folderID,
            folderTitle: folderTitle
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
                depth: depth,
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
            depth: depth,
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

    private func flattenedDescendants(of entity: SumiBookmarkEntity) -> [SumiBookmarkEntity] {
        entity.children.flatMap { child in
            [child] + flattenedDescendants(of: child)
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

    private func saveAndReload() throws {
        guard context.hasChanges else {
            reload()
            return
        }
        do {
            try context.save()
            reload()
        } catch {
            context.rollback()
            throw SumiBookmarkError.saveFailed(error.localizedDescription)
        }
    }

    private func suggestedTitle(for tab: Tab) -> String {
        let title = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !tab.representsSumiEmptySurface {
            return title
        }
        return tab.url.sumiSuggestedTitlePlaceholder ?? tab.url.absoluteString
    }

    private func sanitizedTitle(_ title: String, fallbackURL: URL) -> String {
        title.nilIfTrimmedEmpty
            ?? fallbackURL.sumiSuggestedTitlePlaceholder
            ?? fallbackURL.absoluteString
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

    private func importNode(
        _ node: SumiImportedBookmarkNode,
        into parent: BookmarkEntity,
        knownURLKeys: inout Set<String>,
        summary: inout SumiBookmarkImportSummary
    ) {
        switch node.kind {
        case .folder:
            let folder = BookmarkEntity.makeFolder(
                title: sanitizedFolderTitle(node.title),
                parent: parent,
                context: context
            )
            summary.imported += 1
            for child in node.children {
                importNode(child, into: folder, knownURLKeys: &knownURLKeys, summary: &summary)
            }
        case .bookmark(let url):
            guard Self.canBookmark(url) else {
                summary.failed += 1
                return
            }
            let variantKeys = Set(url.sumiBookmarkButtonURLVariants().map(Self.urlKey))
            if !knownURLKeys.isDisjoint(with: variantKeys) {
                summary.duplicates += 1
                return
            }
            _ = BookmarkEntity.makeBookmark(
                title: sanitizedTitle(node.title, fallbackURL: url),
                url: url.absoluteString,
                parent: parent,
                context: context
            )
            knownURLKeys.formUnion(variantKeys)
            summary.imported += 1
        }
    }

    private func appendExportLines(
        for entities: [BookmarkEntity],
        indent: Int,
        to lines: inout [String]
    ) {
        let prefix = String(repeating: "    ", count: indent)
        for entity in entities {
            let title = htmlEscaped(entity.title?.nilIfTrimmedEmpty ?? "Untitled")
            if entity.isFolder {
                lines.append("\(prefix)<DT><H3>\(title)</H3>")
                lines.append("\(prefix)<DL><p>")
                appendExportLines(for: entity.childrenArray, indent: indent + 1, to: &lines)
                lines.append("\(prefix)</DL><p>")
            } else if let urlString = entity.url,
                      let url = URL(string: urlString)
            {
                lines.append("\(prefix)<DT><A HREF=\"\(htmlEscaped(url.absoluteString))\">\(title)</A>")
            }
        }
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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

    private static func urlKey(_ url: URL) -> String {
        url.absoluteString.lowercased()
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
