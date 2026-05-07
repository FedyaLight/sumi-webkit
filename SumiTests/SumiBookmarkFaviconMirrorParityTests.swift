import CoreData
import XCTest

import Bookmarks
import Persistence
@testable import Sumi

@MainActor
final class SumiBookmarkFaviconMirrorParityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testBookmarkMirrorPersistsSyntheticIDsURLsAndHostsAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkFaviconMirrorParity")
        let bookmarkID = "Mixed-Case-Bookmark-ID"
        let shortcutID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let expectedRecords = [
            BookmarkMirrorRecord(
                uuid: "sumi-favicon-mirror-\(shortcutID.uuidString.lowercased())",
                title: "Shortcut",
                url: "https://shortcuts.example/start",
                parentID: BookmarkEntity.Constants.rootFolderID
            ),
            BookmarkMirrorRecord(
                uuid: "sumi-real-bookmark-\(bookmarkID.lowercased())",
                title: "Bookmark",
                url: "https://bookmarks.example/path",
                parentID: BookmarkEntity.Constants.rootFolderID
            ),
        ]

        do {
            let database = try makeCoreDataDatabase(
                name: "Bookmarks_V6",
                directory: directory,
                modelName: "BookmarksModel",
                preferredBundles: [Bookmarks.bundle, Bundle(for: BookmarkEntity.self)]
            )
            let mirror = SumiBookmarkMirrorManager(database: database)
            mirror.syncBookmarks([
                SumiBookmark(
                    id: bookmarkID,
                    title: "Bookmark",
                    url: try XCTUnwrap(URL(string: "https://bookmarks.example/path")),
                    folderID: nil
                ),
            ])
            mirror.syncShortcutPins([
                ShortcutPin(
                    id: shortcutID,
                    role: .essential,
                    index: 0,
                    launchURL: try XCTUnwrap(URL(string: "https://shortcuts.example/start")),
                    title: "Shortcut"
                ),
            ])

            XCTAssertEqual(mirror.allHosts(), ["bookmarks.example", "shortcuts.example"])
            XCTAssertEqual(try fetchBookmarkMirrorRecords(in: database), expectedRecords)
        }

        let reopenedDatabase = try makeCoreDataDatabase(
            name: "Bookmarks_V6",
            directory: directory,
            modelName: "BookmarksModel",
            preferredBundles: [Bookmarks.bundle, Bundle(for: BookmarkEntity.self)]
        )
        let reopenedMirror = SumiBookmarkMirrorManager(database: reopenedDatabase)

        XCTAssertEqual(reopenedMirror.allHosts(), ["bookmarks.example", "shortcuts.example"])
        XCTAssertEqual(try fetchBookmarkMirrorRecords(in: reopenedDatabase), expectedRecords)
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeCoreDataDatabase(
        name: String,
        directory: URL,
        modelName: String,
        preferredBundles: [Bundle]
    ) throws -> CoreDataDatabase {
        if modelName == "Favicons" {
            FaviconValueTransformers.register()
        }
        let model = try XCTUnwrap(loadModel(named: modelName, preferredBundles: preferredBundles))
        let database = CoreDataDatabase(name: name, containerLocation: directory, model: model)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
        }
        _ = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "\(name)LoadWait")
        if let loadError {
            throw loadError
        }
        return database
    }

    private func loadModel(named modelName: String, preferredBundles: [Bundle]) -> NSManagedObjectModel? {
        let bundles = (preferredBundles + [.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks)
            .reduce(into: [String: Bundle]()) { result, bundle in
                guard bundle.resourceURL != nil else { return }
                result[bundle.bundleURL.path] = bundle
            }
            .values

        for bundle in bundles {
            if let model = CoreDataDatabase.loadModel(from: bundle, named: modelName) {
                return model
            }
        }
        return nil
    }

    private func fetchBookmarkMirrorRecords(in database: CoreDataDatabase) throws -> [BookmarkMirrorRecord] {
        let context = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiBookmarkFaviconMirrorParityRead"
        )
        var result = Result<[BookmarkMirrorRecord], Error>.success([])
        context.performAndWait {
            do {
                let request = BookmarkEntity.fetchRequest()
                request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "%K BEGINSWITH %@", #keyPath(BookmarkEntity.uuid), "sumi-favicon-mirror-"),
                    NSPredicate(format: "%K BEGINSWITH %@", #keyPath(BookmarkEntity.uuid), "sumi-real-bookmark-"),
                ])
                request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BookmarkEntity.uuid), ascending: true)]
                request.returnsObjectsAsFaults = false
                result = .success(try context.fetch(request).map {
                    BookmarkMirrorRecord(
                        uuid: $0.uuid ?? "",
                        title: $0.title ?? "",
                        url: $0.url ?? "",
                        parentID: $0.parent?.uuid
                    )
                })
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }
}

private struct BookmarkMirrorRecord: Equatable {
    let uuid: String
    let title: String
    let url: String
    let parentID: String?
}

final class SumiBookmarkFaviconStoreParityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testFaviconStorePersistsFaviconsAndReferencesAcrossReopen() async throws {
        let directory = try temporaryDirectory(named: "SumiFaviconStoreParity")
        let faviconID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let hostReferenceID = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"))
        let urlReferenceID = try XCTUnwrap(UUID(uuidString: "cccccccc-dddd-eeee-ffff-aaaaaaaaaaaa"))
        let faviconURL = try XCTUnwrap(URL(string: "https://assets.example/favicon.ico"))
        let documentURL = try XCTUnwrap(URL(string: "https://docs.example/start"))
        let dateCreated = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 1,
            day: 2,
            hour: 3,
            minute: 4,
            second: 5
        ).date)

        do {
            let database = try makeCoreDataDatabase(
                name: "Favicons",
                directory: directory,
                modelName: "Favicons",
                preferredBundles: [.main]
            )
            let store = FaviconStore(database: database)

            try await store.save([
                Favicon(
                    identifier: faviconID,
                    url: faviconURL,
                    image: nil,
                    relation: .favicon,
                    documentUrl: documentURL,
                    dateCreated: dateCreated
                ),
            ])
            try await store.save(hostReference: FaviconHostReference(
                identifier: hostReferenceID,
                smallFaviconUrl: faviconURL,
                mediumFaviconUrl: nil,
                host: "docs.example",
                documentUrl: documentURL,
                dateCreated: dateCreated
            ))
            try await store.save(urlReference: FaviconUrlReference(
                identifier: urlReferenceID,
                smallFaviconUrl: faviconURL,
                mediumFaviconUrl: nil,
                documentUrl: documentURL,
                dateCreated: dateCreated
            ))
        }

        let reopenedDatabase = try makeCoreDataDatabase(
            name: "Favicons",
            directory: directory,
            modelName: "Favicons",
            preferredBundles: [.main]
        )
        let reopenedStore = FaviconStore(database: reopenedDatabase)
        let favicons = try await reopenedStore.loadFavicons()
        let (hostReferences, urlReferences) = try await reopenedStore.loadFaviconReferences()

        XCTAssertEqual(favicons.map(\.identifier), [faviconID])
        XCTAssertEqual(favicons.first?.url, faviconURL)
        XCTAssertEqual(favicons.first?.documentUrl, documentURL)
        XCTAssertEqual(favicons.first?.relation, .favicon)
        XCTAssertEqual(hostReferences.map(\.identifier), [hostReferenceID])
        XCTAssertEqual(hostReferences.first?.host, "docs.example")
        XCTAssertEqual(hostReferences.first?.smallFaviconUrl, faviconURL)
        XCTAssertEqual(hostReferences.first?.documentUrl, documentURL)
        XCTAssertEqual(urlReferences.map(\.identifier), [urlReferenceID])
        XCTAssertEqual(urlReferences.first?.smallFaviconUrl, faviconURL)
        XCTAssertEqual(urlReferences.first?.documentUrl, documentURL)
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeCoreDataDatabase(
        name: String,
        directory: URL,
        modelName: String,
        preferredBundles: [Bundle]
    ) throws -> CoreDataDatabase {
        if modelName == "Favicons" {
            FaviconValueTransformers.register()
        }
        let model = try XCTUnwrap(loadModel(named: modelName, preferredBundles: preferredBundles))
        let database = CoreDataDatabase(name: name, containerLocation: directory, model: model)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
        }
        _ = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "\(name)LoadWait")
        if let loadError {
            throw loadError
        }
        return database
    }

    private func loadModel(named modelName: String, preferredBundles: [Bundle]) -> NSManagedObjectModel? {
        let bundles = (preferredBundles + [.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks)
            .reduce(into: [String: Bundle]()) { result, bundle in
                guard bundle.resourceURL != nil else { return }
                result[bundle.bundleURL.path] = bundle
            }
            .values

        for bundle in bundles {
            if let model = CoreDataDatabase.loadModel(from: bundle, named: modelName) {
                return model
            }
        }
        return nil
    }
}
