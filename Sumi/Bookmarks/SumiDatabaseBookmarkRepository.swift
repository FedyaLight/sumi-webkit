import Foundation
import OSLog

@MainActor
final class SumiDatabaseBookmarkRepository:
    SumiBookmarkRepository,
    @unchecked Sendable
{
    private static let log = Logger.sumi(category: "Bookmarks")
    nonisolated private static let favoritesFolderUUID = UUID(
        uuidString: SumiBookmarkConstants.favoritesFolderID
    )!
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
        do {
            try database.transaction { connection in
                var records = try connection.bookmarks.all()
                guard try Self.ensureFavoritesFolder(in: &records) else { return }
                try connection.bookmarks.replaceAll(with: records)
            }
        } catch {
            Self.log.error(
                "Failed to prepare Favorites: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func fetchBookmarks() -> [SumiBookmark] {
        records().compactMap(bookmark)
    }

    func snapshot(sortMode: SumiBookmarkSortMode) -> SumiBookmarksSnapshot {
        makeSnapshot(records: records(), sortMode: sortMode)
    }

    func entity(
        id: String,
        sortMode: SumiBookmarkSortMode = .manual
    ) -> SumiBookmarkEntity? {
        snapshot(sortMode: sortMode).entitiesByID[id]
    }

    func openableURLs(for ids: [String]) -> [URL] {
        let snapshot = snapshot(sortMode: .manual)
        func urls(in entity: SumiBookmarkEntity) -> [URL] {
            if let url = entity.url { return [url] }
            return entity.children.flatMap(urls)
        }
        return ids.compactMap { snapshot.entitiesByID[$0] }.flatMap(urls)
    }

    func createBookmark(
        url: URL,
        title: String,
        folderID: String?
    ) throws -> SumiBookmark {
        let parentID = try resolvedBookmarkFolderID(folderID, in: records())
        let record = BookmarkRecord(
            id: UUID(),
            parentID: parentID,
            name: title,
            urlString: url.absoluteString,
            kind: SumiBookmarkEntityKind.bookmark.rawValue,
            index: 0
        )
        try mutate { records in
            recordIndex(&records, parentID: parentID)
            var inserted = record
            inserted.index = nextIndex(in: records, parentID: parentID)
            records.append(inserted)
        }
        return bookmark(record)!
    }

    func updateBookmark(
        id: String,
        title: String,
        url: URL,
        folderID: String?
    ) throws -> SumiBookmark {
        guard let identifier = UUID(uuidString: id) else {
            throw SumiBookmarkError.missingBookmark
        }
        var result: BookmarkRecord?
        try mutate { records in
            guard let index = records.firstIndex(where: {
                $0.id == identifier && $0.kind == SumiBookmarkEntityKind.bookmark.rawValue
            }) else {
                throw SumiBookmarkError.missingBookmark
            }
            let parentID = try resolvedBookmarkFolderID(folderID, in: records)
            let oldParentID = records[index].parentID
            records[index].name = title
            records[index].urlString = url.absoluteString
            if oldParentID != parentID {
                records[index].parentID = parentID
                records[index].index = nextIndex(in: records, parentID: parentID)
                normalize(&records, parentID: oldParentID)
            }
            result = records[index]
        }
        guard let result, let bookmark = bookmark(result) else {
            throw SumiBookmarkError.missingBookmark
        }
        return bookmark
    }

    func createFolder(
        title: String,
        parentID: String?
    ) throws -> SumiBookmarkEntity {
        let all = records()
        let resolvedParentID = try resolvedFolderID(parentID, in: all)
        let folder = BookmarkRecord(
            id: UUID(),
            parentID: resolvedParentID,
            name: title,
            urlString: nil,
            kind: SumiBookmarkEntityKind.folder.rawValue,
            index: nextIndex(in: all, parentID: resolvedParentID)
        )
        try mutate { $0.append(folder) }
        return entity(id: folder.id.uuidString) ?? emptyFolder(from: folder)
    }

    func createFolderWithBookmarks(
        title: String,
        parentID: String?,
        bookmarks: [SumiBookmarkCreateRequest]
    ) throws -> SumiBookmarkFolderCreateResult {
        let all = records()
        let resolvedParentID = try resolvedFolderID(parentID, in: all)
        let folder = BookmarkRecord(
            id: UUID(),
            parentID: resolvedParentID,
            name: title,
            urlString: nil,
            kind: SumiBookmarkEntityKind.folder.rawValue,
            index: nextIndex(in: all, parentID: resolvedParentID)
        )
        let created = bookmarks.enumerated().map { index, bookmark in
            BookmarkRecord(
                id: UUID(),
                parentID: folder.id,
                name: bookmark.title,
                urlString: bookmark.url.absoluteString,
                kind: SumiBookmarkEntityKind.bookmark.rawValue,
                index: index
            )
        }
        try mutate {
            $0.append(folder)
            $0.append(contentsOf: created)
        }
        return SumiBookmarkFolderCreateResult(
            folder: entity(id: folder.id.uuidString) ?? emptyFolder(from: folder),
            bookmarks: created.compactMap(bookmark)
        )
    }

    func updateFolder(
        id: String,
        title: String,
        parentID: String?
    ) throws -> SumiBookmarkEntity {
        guard !SumiBookmarkConstants.isProtectedFolderID(id),
              let identifier = UUID(uuidString: id) else {
            throw SumiBookmarkError.missingFolder
        }
        try mutate { records in
            guard let index = records.firstIndex(where: {
                $0.id == identifier && $0.kind == SumiBookmarkEntityKind.folder.rawValue
            }) else {
                throw SumiBookmarkError.missingFolder
            }
            let destination = try resolvedFolderID(parentID, in: records)
            if destination == identifier
                || destination.map({ descendants(of: identifier, in: records).contains($0) }) == true {
                throw SumiBookmarkError.cannotMoveFolderIntoDescendant
            }
            let oldParent = records[index].parentID
            records[index].name = title
            if oldParent != destination {
                records[index].parentID = destination
                records[index].index = nextIndex(in: records, parentID: destination)
                normalize(&records, parentID: oldParent)
            }
        }
        guard let folder = entity(id: id) else {
            throw SumiBookmarkError.missingFolder
        }
        return folder
    }

    func removeEntities(ids: [String]) throws -> [SumiBookmark] {
        if ids.contains(where: SumiBookmarkConstants.isProtectedFolderID) {
            throw SumiBookmarkError.cannotDeleteRootFolder
        }
        let identifiers = Set(ids.compactMap(UUID.init(uuidString:)))
        var removed: [SumiBookmark] = []
        try mutate { records in
            var removal = identifiers
            for id in identifiers {
                removal.formUnion(descendants(of: id, in: records))
            }
            removed = records
                .filter { removal.contains($0.id) }
                .compactMap(bookmark)
            let affectedParents = Set(
                records.filter { removal.contains($0.id) }.map(\.parentID)
            )
            records.removeAll { removal.contains($0.id) }
            for parentID in affectedParents {
                normalize(&records, parentID: parentID)
            }
        }
        return removed
    }

    func moveEntities(
        ids: [String],
        toParentID parentID: String?,
        atIndex index: Int?
    ) throws {
        if ids.contains(where: SumiBookmarkConstants.isProtectedFolderID) {
            throw SumiBookmarkError.cannotDeleteRootFolder
        }
        let identifiers = ids.compactMap(UUID.init(uuidString:))
        try mutate { records in
            let requestedDestination = try resolvedFolderID(parentID, in: records)
            let includesBookmark = records.contains {
                identifiers.contains($0.id)
                    && $0.kind == SumiBookmarkEntityKind.bookmark.rawValue
            }
            let destination = requestedDestination == nil && includesBookmark
                ? Self.favoritesFolderUUID
                : requestedDestination
            for id in identifiers where destination == id
                || destination.map({ descendants(of: id, in: records).contains($0) }) == true {
                throw SumiBookmarkError.cannotMoveFolderIntoDescendant
            }
            let oldParents = Set(
                records.filter { identifiers.contains($0.id) }.map(\.parentID)
            )
            let moving = identifiers.compactMap { id in
                records.first(where: { $0.id == id })
            }
            records.removeAll { identifiers.contains($0.id) }
            var siblings = records
                .filter { $0.parentID == destination }
                .sorted(by: recordOrder)
            let insertionIndex = min(max(0, index ?? siblings.count), siblings.count)
            siblings.insert(contentsOf: moving, at: insertionIndex)
            for (position, sibling) in siblings.enumerated() {
                guard let recordIndex = records.firstIndex(where: {
                    $0.id == sibling.id
                }) else {
                    var inserted = sibling
                    inserted.parentID = destination
                    inserted.index = position
                    records.append(inserted)
                    continue
                }
                records[recordIndex].parentID = destination
                records[recordIndex].index = position
            }
            for oldParent in oldParents where oldParent != destination {
                normalize(&records, parentID: oldParent)
            }
        }
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String?,
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        try mutateImport(
            bookmarks,
            parentID: parentID,
            replaceExisting: false,
            acceptsURL: acceptsURL,
            urlKeys: urlKeys
        )
    }

    func replaceBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        try mutateImport(
            bookmarks,
            parentID: nil,
            replaceExisting: true,
            acceptsURL: acceptsURL,
            urlKeys: urlKeys
        )
    }

    func restoreSnapshot(_ snapshot: SumiBookmarksSnapshot) throws {
        var restored: [BookmarkRecord] = []
        func append(_ entities: [SumiBookmarkEntity], parentID: UUID?) throws {
            for (position, entity) in entities.enumerated() {
                guard let id = UUID(uuidString: entity.id) else {
                    throw SumiBookmarkError.saveFailed(
                        "Bookmark identifier is invalid: \(entity.id)"
                    )
                }
                restored.append(
                    BookmarkRecord(
                        id: id,
                        parentID: parentID,
                        name: entity.title,
                        urlString: entity.url?.absoluteString,
                        kind: entity.kind.rawValue,
                        index: position
                    )
                )
                try append(entity.children, parentID: id)
            }
        }
        try append(snapshot.root.children, parentID: nil)
        _ = try Self.ensureFavoritesFolder(in: &restored)
        try database.transaction {
            try $0.bookmarks.replaceAll(with: restored)
        }
    }

    func exportBookmarksHTML(to destination: URL) throws {
        do {
            try BookmarkHTMLExporter.exportBookmarksHTML(
                root: snapshot(sortMode: .manual).root
            ).write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw SumiBookmarkError.exportFailed(error.localizedDescription)
        }
    }

    private func mutate(
        _ operation: (inout [BookmarkRecord]) throws -> Void
    ) throws {
        try database.transaction { connection in
            var records = try connection.bookmarks.all()
            try operation(&records)
            try connection.bookmarks.replaceAll(with: records)
        }
    }

    private func mutateImport(
        _ nodes: [SumiBookmarkImportNode],
        parentID: String?,
        replaceExisting: Bool,
        acceptsURL: (URL) -> Bool,
        urlKeys: (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        var summary = SumiBookmarksImportSummary(
            successful: 0,
            duplicates: 0,
            failed: 0
        )
        try database.transaction { connection in
            var records = replaceExisting
                ? []
                : try connection.bookmarks.all()
            _ = try Self.ensureFavoritesFolder(in: &records)
            let destination = try resolvedFolderID(parentID, in: records)
            var knownKeys = Set(
                records.compactMap { $0.urlString.flatMap(URL.init(string:)) }
                    .flatMap(urlKeys)
            )
            func append(
                _ nodes: [SumiBookmarkImportNode],
                parentID: UUID?
            ) {
                for node in nodes {
                    switch node.type {
                    case .folder:
                        let id = UUID()
                        records.append(
                            BookmarkRecord(
                                id: id,
                                parentID: parentID,
                                name: node.name.nilIfTrimmedEmpty ?? "Folder",
                                urlString: nil,
                                kind: SumiBookmarkEntityKind.folder.rawValue,
                                index: nextIndex(in: records, parentID: parentID)
                            )
                        )
                        summary.successful += 1
                        append(node.children ?? [], parentID: id)
                    case .bookmark, .favorite:
                        guard let url = node.url, acceptsURL(url) else {
                            summary.failed += 1
                            continue
                        }
                        let keys = urlKeys(url)
                        guard knownKeys.isDisjoint(with: keys) else {
                            summary.duplicates += 1
                            continue
                        }
                        records.append(
                            BookmarkRecord(
                                id: UUID(),
                                parentID: parentID ?? Self.favoritesFolderUUID,
                                name: node.name.nilIfTrimmedEmpty
                                    ?? url.host
                                    ?? url.absoluteString,
                                urlString: url.absoluteString,
                                kind: SumiBookmarkEntityKind.bookmark.rawValue,
                                index: nextIndex(in: records, parentID: parentID)
                            )
                        )
                        knownKeys.formUnion(keys)
                        summary.successful += 1
                    }
                }
            }
            append(nodes, parentID: destination)
            try connection.bookmarks.replaceAll(with: records)
        }
        return summary
    }

    private func records() -> [BookmarkRecord] {
        do {
            return try database.read { try $0.bookmarks.all() }
        } catch {
            Self.log.error(
                "Failed to read bookmarks: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func makeSnapshot(
        records: [BookmarkRecord],
        sortMode: SumiBookmarkSortMode
    ) -> SumiBookmarksSnapshot {
        let recordsByParent = Dictionary(grouping: records, by: \.parentID)
        var entitiesByID: [String: SumiBookmarkEntity] = [:]
        func build(
            _ record: BookmarkRecord,
            parentTitle: String?,
            visited: Set<UUID>
        ) -> SumiBookmarkEntity? {
            guard !visited.contains(record.id),
                  let kind = SumiBookmarkEntityKind(rawValue: record.kind) else {
                return nil
            }
            let children = sorted(
                recordsByParent[record.id] ?? [],
                mode: sortMode
            ).compactMap {
                build(
                    $0,
                    parentTitle: record.name,
                    visited: visited.union([record.id])
                )
            }
            let node = SumiBookmarkEntity(
                id: record.id.uuidString,
                kind: kind,
                title: record.name,
                url: record.urlString.flatMap(URL.init(string:)),
                parentID: record.parentID?.uuidString
                    ?? SumiBookmarkConstants.rootFolderID,
                parentTitle: parentTitle ?? "Bookmarks",
                children: children,
                childBookmarkCount: children.reduce(0) {
                    $0 + ($1.isBookmark ? 1 : $1.childBookmarkCount)
                }
            )
            entitiesByID[node.id] = node
            return node
        }
        let sortedTopLevel = sorted(recordsByParent[nil] ?? [], mode: sortMode)
        let orderedTopLevel = sortedTopLevel.filter {
            $0.id == Self.favoritesFolderUUID
        } + sortedTopLevel.filter {
            $0.id != Self.favoritesFolderUUID
        }
        let children = orderedTopLevel
            .compactMap { build($0, parentTitle: "Bookmarks", visited: []) }
        let root = SumiBookmarkEntity(
            id: SumiBookmarkConstants.rootFolderID,
            kind: .folder,
            title: "Bookmarks",
            url: nil,
            parentID: nil,
            parentTitle: nil,
            children: children,
            childBookmarkCount: children.reduce(0) {
                $0 + ($1.isBookmark ? 1 : $1.childBookmarkCount)
            }
        )
        entitiesByID[root.id] = root
        var flattenedFolders: [SumiBookmarkFolder] = []
        func flatten(_ entity: SumiBookmarkEntity, depth: Int) {
            guard entity.isFolder else { return }
            flattenedFolders.append(
                .init(id: entity.id, title: entity.title, depth: depth)
            )
            entity.children.forEach { flatten($0, depth: depth + 1) }
        }
        root.children.forEach { flatten($0, depth: 0) }
        return SumiBookmarksSnapshot(
            root: root,
            flattenedFolders: flattenedFolders,
            entitiesByID: entitiesByID
        )
    }

    private func sorted(
        _ records: [BookmarkRecord],
        mode: SumiBookmarkSortMode
    ) -> [BookmarkRecord] {
        switch mode {
        case .manual:
            return records.sorted(by: recordOrder)
        case .nameAscending:
            return records.sorted { titleOrder($0, $1, ascending: true) }
        case .nameDescending:
            return records.sorted { titleOrder($0, $1, ascending: false) }
        case .addressAscending:
            return records.sorted { addressOrder($0, $1, ascending: true) }
        case .addressDescending:
            return records.sorted { addressOrder($0, $1, ascending: false) }
        }
    }

    private func titleOrder(
        _ lhs: BookmarkRecord,
        _ rhs: BookmarkRecord,
        ascending: Bool
    ) -> Bool {
        let lhsFolder = lhs.kind == SumiBookmarkEntityKind.folder.rawValue
        let rhsFolder = rhs.kind == SumiBookmarkEntityKind.folder.rawValue
        if lhsFolder != rhsFolder { return lhsFolder }
        let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return ascending
            ? result == .orderedAscending
            : result == .orderedDescending
    }

    private func addressOrder(
        _ lhs: BookmarkRecord,
        _ rhs: BookmarkRecord,
        ascending: Bool
    ) -> Bool {
        let lhsFolder = lhs.kind == SumiBookmarkEntityKind.folder.rawValue
        let rhsFolder = rhs.kind == SumiBookmarkEntityKind.folder.rawValue
        if lhsFolder != rhsFolder { return lhsFolder }
        let result = (lhs.urlString ?? lhs.name).localizedCaseInsensitiveCompare(
            rhs.urlString ?? rhs.name
        )
        if result == .orderedSame {
            return titleOrder(lhs, rhs, ascending: ascending)
        }
        return ascending
            ? result == .orderedAscending
            : result == .orderedDescending
    }

    private func resolvedFolderID(
        _ value: String?,
        in records: [BookmarkRecord]
    ) throws -> UUID? {
        guard let value, value != SumiBookmarkConstants.rootFolderID else {
            return nil
        }
        guard let id = UUID(uuidString: value),
              records.contains(where: {
                  $0.id == id && $0.kind == SumiBookmarkEntityKind.folder.rawValue
              }) else {
            throw SumiBookmarkError.missingFolder
        }
        return id
    }

    private func resolvedBookmarkFolderID(
        _ value: String?,
        in records: [BookmarkRecord]
    ) throws -> UUID {
        try resolvedFolderID(value, in: records) ?? Self.favoritesFolderUUID
    }

    @discardableResult
    private static func ensureFavoritesFolder(
        in records: inout [BookmarkRecord]
    ) throws -> Bool {
        var changed = false
        if let index = records.firstIndex(where: { $0.id == favoritesFolderUUID }) {
            guard records[index].kind == SumiBookmarkEntityKind.folder.rawValue else {
                throw SumiBookmarkError.saveFailed("Favorites identifier is already in use.")
            }
            if records[index].parentID != nil {
                records[index].parentID = nil
                changed = true
            }
            if records[index].name != "Favorites" {
                records[index].name = "Favorites"
                changed = true
            }
        } else {
            records.append(
                BookmarkRecord(
                    id: favoritesFolderUUID,
                    parentID: nil,
                    name: "Favorites",
                    urlString: nil,
                    kind: SumiBookmarkEntityKind.folder.rawValue,
                    index: 0
                )
            )
            changed = true
        }

        let directBookmarks = records
            .filter {
                $0.parentID == nil
                    && $0.kind == SumiBookmarkEntityKind.bookmark.rawValue
            }
            .sorted(by: recordOrder)
        if !directBookmarks.isEmpty {
            let nextChildIndex = (records
                .filter { $0.parentID == favoritesFolderUUID }
                .map(\.index)
                .max() ?? -1) + 1
            for (offset, bookmark) in directBookmarks.enumerated() {
                guard let index = records.firstIndex(where: { $0.id == bookmark.id }) else {
                    continue
                }
                records[index].parentID = favoritesFolderUUID
                records[index].index = nextChildIndex + offset
            }
            changed = true
        }

        let topLevel = records
            .filter { $0.parentID == nil }
            .sorted(by: recordOrder)
        let orderedTopLevel = topLevel
            .filter { $0.id == favoritesFolderUUID }
            + topLevel.filter { $0.id != favoritesFolderUUID }
        for (position, record) in orderedTopLevel.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == record.id }) else {
                continue
            }
            if records[index].index != position {
                records[index].index = position
                changed = true
            }
        }
        return changed
    }

    private func descendants(
        of id: UUID,
        in records: [BookmarkRecord]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        var frontier = [id]
        while let parent = frontier.popLast() {
            for child in records where child.parentID == parent {
                if result.insert(child.id).inserted {
                    frontier.append(child.id)
                }
            }
        }
        return result
    }

    nonisolated private func nextIndex(
        in records: [BookmarkRecord],
        parentID: UUID?
    ) -> Int {
        (records.filter { $0.parentID == parentID }.map(\.index).max() ?? -1) + 1
    }

    private func normalize(
        _ records: inout [BookmarkRecord],
        parentID: UUID?
    ) {
        for (position, record) in records
            .filter({ $0.parentID == parentID })
            .sorted(by: recordOrder)
            .enumerated() {
            guard let index = records.firstIndex(where: { $0.id == record.id })
            else { continue }
            records[index].index = position
        }
    }

    private func recordIndex(
        _ records: inout [BookmarkRecord],
        parentID: UUID?
    ) {
        normalize(&records, parentID: parentID)
    }

    nonisolated private static func recordOrder(
        _ lhs: BookmarkRecord,
        _ rhs: BookmarkRecord
    ) -> Bool {
        lhs.index == rhs.index
            ? lhs.id.uuidString < rhs.id.uuidString
            : lhs.index < rhs.index
    }

    private func recordOrder(
        _ lhs: BookmarkRecord,
        _ rhs: BookmarkRecord
    ) -> Bool {
        Self.recordOrder(lhs, rhs)
    }

    private func bookmark(_ record: BookmarkRecord) -> SumiBookmark? {
        guard record.kind == SumiBookmarkEntityKind.bookmark.rawValue,
              let value = record.urlString,
              let url = URL(string: value) else {
            return nil
        }
        return SumiBookmark(
            id: record.id.uuidString,
            title: record.name,
            url: url,
            folderID: record.parentID?.uuidString
        )
    }

    private func emptyFolder(
        from record: BookmarkRecord
    ) -> SumiBookmarkEntity {
        .init(
            id: record.id.uuidString,
            kind: .folder,
            title: record.name,
            url: nil,
            parentID: record.parentID?.uuidString
                ?? SumiBookmarkConstants.rootFolderID,
            parentTitle: nil,
            children: [],
            childBookmarkCount: 0
        )
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
