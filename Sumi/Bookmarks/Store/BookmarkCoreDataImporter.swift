//
//  BookmarkCoreDataImporter.swift
//
//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//

import CoreData
import Foundation

/// Imports parsed bookmark trees into a main-queue Core Data context.
/// Main-actor-isolated: it works the context directly, in the same
/// queue-confinement style as `SumiCoreDataBookmarkRepository` that owns it.
@MainActor
final class BookmarkCoreDataImporter {
    typealias URLAcceptance = (URL) -> Bool
    typealias URLKeys = (URL) -> Set<String>

    private let context: NSManagedObjectContext
    private let acceptsURL: URLAcceptance
    private let urlKeys: URLKeys

    init(
        context: NSManagedObjectContext,
        acceptsURL: @escaping URLAcceptance = BookmarkCoreDataImporter.defaultAcceptsURL(_:),
        urlKeys: @escaping URLKeys = BookmarkCoreDataImporter.defaultURLKeys(for:)
    ) {
        self.context = context
        self.acceptsURL = acceptsURL
        self.urlKeys = urlKeys
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parent: BookmarkEntity? = nil
    ) throws -> SumiBookmarksImportSummary {
        do {
            let targetParent = try parent ?? requiredRootFolder()
            var knownURLKeys = try existingURLKeys()
            var summary = SumiBookmarksImportSummary(successful: 0, duplicates: 0, failed: 0)

            for node in bookmarks {
                importNode(node, into: targetParent, knownURLKeys: &knownURLKeys, summary: &summary)
            }

            if context.hasChanges {
                try context.save()
            }
            return summary
        } catch {
            context.rollback()
            throw error
        }
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

    private func importNode(
        _ node: SumiBookmarkImportNode,
        into parent: BookmarkEntity,
        knownURLKeys: inout Set<String>,
        summary: inout SumiBookmarksImportSummary
    ) {
        if node.isInvalidBookmark {
            summary.failed += 1
            return
        }

        switch node.type {
        case .folder:
            let folder = BookmarkEntity.makeFolder(
                title: sanitizedFolderTitle(node.name),
                parent: parent,
                context: context
            )
            summary.successful += 1
            for child in node.children ?? [] {
                importNode(child, into: folder, knownURLKeys: &knownURLKeys, summary: &summary)
            }
        case .bookmark, .favorite:
            guard let url = node.url, acceptsURL(url) else {
                summary.failed += 1
                return
            }

            let keys = urlKeys(url)
            if !knownURLKeys.isDisjoint(with: keys) {
                summary.duplicates += 1
                return
            }

            _ = BookmarkEntity.makeBookmark(
                title: sanitizedTitle(node.name, fallbackURL: url),
                url: url.absoluteString,
                parent: parent,
                context: context
            )
            knownURLKeys.formUnion(keys)
            summary.successful += 1
        }
    }

    nonisolated static func defaultAcceptsURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return url.host?.isEmpty == false
    }

    nonisolated static func defaultURLKeys(for url: URL) -> Set<String> {
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
