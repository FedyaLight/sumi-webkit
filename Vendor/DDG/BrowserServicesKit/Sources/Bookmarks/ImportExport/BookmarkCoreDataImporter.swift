//
//  BookmarkCoreDataImporter.swift
//

import CoreData
import Foundation

public final class BookmarkCoreDataImporter {
    public typealias URLAcceptance = (URL) -> Bool
    public typealias URLKeys = (URL) -> Set<String>

    private let context: NSManagedObjectContext
    private let acceptsURL: URLAcceptance
    private let urlKeys: URLKeys

    public init(
        context: NSManagedObjectContext,
        acceptsURL: @escaping URLAcceptance = BookmarkCoreDataImporter.defaultAcceptsURL(_:),
        urlKeys: @escaping URLKeys = BookmarkCoreDataImporter.defaultURLKeys(for:)
    ) {
        self.context = context
        self.acceptsURL = acceptsURL
        self.urlKeys = urlKeys
    }

    public func importBookmarks(_ bookmarks: [BookmarkOrFolder], parent: BookmarkEntity? = nil) throws -> BookmarksImportSummary {
        var result: Result<BookmarksImportSummary, Error>!
        context.performAndWait {
            do {
                let targetParent = try parent ?? requiredRootFolder()
                var knownURLKeys = try existingURLKeys()
                var summary = BookmarksImportSummary(successful: 0, duplicates: 0, failed: 0)

                for bookmark in bookmarks {
                    importBookmarkOrFolder(bookmark, into: targetParent, knownURLKeys: &knownURLKeys, summary: &summary)
                }

                if context.hasChanges {
                    try context.save()
                }
                result = .success(summary)
            } catch {
                context.rollback()
                result = .failure(error)
            }
        }
        return try result.get()
    }

    private func requiredRootFolder() throws -> BookmarkEntity {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            throw BookmarkImportExportError.missingRootFolder
        }
        return root
    }

    private func existingURLKeys() throws -> Set<String> {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == false AND %K == false AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.propertiesToFetch = [#keyPath(BookmarkEntity.url)]

        return try context.fetch(request).reduce(into: Set<String>()) { keys, bookmark in
            guard let urlString = bookmark.url,
                  let url = URL(string: urlString)
            else {
                return
            }
            keys.formUnion(urlKeys(url))
        }
    }

    private func importBookmarkOrFolder(
        _ bookmarkOrFolder: BookmarkOrFolder,
        into parent: BookmarkEntity,
        knownURLKeys: inout Set<String>,
        summary: inout BookmarksImportSummary
    ) {
        if bookmarkOrFolder.isInvalidBookmark {
            summary.failed += 1
            return
        }

        switch bookmarkOrFolder.type {
        case .folder:
            let folder = BookmarkEntity.makeFolder(
                title: sanitizedFolderTitle(bookmarkOrFolder.name),
                parent: parent,
                context: context
            )
            summary.successful += 1
            for child in bookmarkOrFolder.children ?? [] {
                importBookmarkOrFolder(child, into: folder, knownURLKeys: &knownURLKeys, summary: &summary)
            }
        case .bookmark, .favorite:
            guard let url = bookmarkOrFolder.url, acceptsURL(url) else {
                summary.failed += 1
                return
            }

            let keys = urlKeys(url)
            if !knownURLKeys.isDisjoint(with: keys) {
                summary.duplicates += 1
                return
            }

            _ = BookmarkEntity.makeBookmark(
                title: sanitizedTitle(bookmarkOrFolder.name, fallbackURL: url),
                url: url.absoluteString,
                parent: parent,
                context: context
            )
            knownURLKeys.formUnion(keys)
            summary.successful += 1
        }
    }

    public static func defaultAcceptsURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return url.host?.isEmpty == false
    }

    public static func defaultURLKeys(for url: URL) -> Set<String> {
        [url.absoluteString.lowercased()]
    }

    private func sanitizedFolderTitle(_ title: String) -> String {
        title.nilIfTrimmedEmpty ?? "Folder"
    }

    private func sanitizedTitle(_ title: String, fallbackURL: URL) -> String {
        title.nilIfTrimmedEmpty ?? fallbackURL.host ?? fallbackURL.absoluteString
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
