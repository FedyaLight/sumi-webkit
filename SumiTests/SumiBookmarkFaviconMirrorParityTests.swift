import CoreData
import XCTest

import Bookmarks
@testable import Sumi

@MainActor
final class SumiBookmarkFaviconMirrorParityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
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

    func testBookmarkMirrorUpdatesAndDeletesSyntheticRecordsAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkFaviconMirrorUpdateDeleteParity")
        let keptBookmarkID = "Bookmark-To-Keep"
        let deletedBookmarkID = "Bookmark-To-Delete"
        let keptShortcutID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"))
        let deletedShortcutID = try XCTUnwrap(UUID(uuidString: "cccccccc-1111-2222-3333-dddddddddddd"))

        let expectedRecords = [
            BookmarkMirrorRecord(
                uuid: "sumi-favicon-mirror-\(keptShortcutID.uuidString.lowercased())",
                title: "Updated Shortcut",
                url: "https://updated-shortcuts.example/home",
                parentID: BookmarkEntity.Constants.rootFolderID
            ),
            BookmarkMirrorRecord(
                uuid: "sumi-real-bookmark-\(keptBookmarkID.lowercased())",
                title: "Updated Bookmark",
                url: "https://updated-bookmarks.example/final",
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
                    id: keptBookmarkID,
                    title: "Initial Bookmark",
                    url: try XCTUnwrap(URL(string: "https://initial-bookmarks.example/start")),
                    folderID: nil
                ),
                SumiBookmark(
                    id: deletedBookmarkID,
                    title: "Deleted Bookmark",
                    url: try XCTUnwrap(URL(string: "https://deleted-bookmarks.example/start")),
                    folderID: nil
                ),
            ])
            mirror.syncShortcutPins([
                ShortcutPin(
                    id: keptShortcutID,
                    role: .essential,
                    index: 0,
                    launchURL: try XCTUnwrap(URL(string: "https://initial-shortcuts.example/start")),
                    title: "Initial Shortcut"
                ),
                ShortcutPin(
                    id: deletedShortcutID,
                    role: .spacePinned,
                    index: 1,
                    launchURL: try XCTUnwrap(URL(string: "https://deleted-shortcuts.example/start")),
                    title: "Deleted Shortcut"
                ),
            ])

            mirror.syncBookmarks([
                SumiBookmark(
                    id: keptBookmarkID,
                    title: "Updated Bookmark",
                    url: try XCTUnwrap(URL(string: "https://updated-bookmarks.example/final")),
                    folderID: nil
                ),
            ])
            mirror.syncShortcutPins([
                ShortcutPin(
                    id: keptShortcutID,
                    role: .essential,
                    index: 0,
                    launchURL: try XCTUnwrap(URL(string: "https://updated-shortcuts.example/home")),
                    title: "Updated Shortcut"
                ),
            ])

            XCTAssertEqual(mirror.allHosts(), ["updated-bookmarks.example", "updated-shortcuts.example"])
            XCTAssertEqual(try fetchBookmarkMirrorRecords(in: database), expectedRecords)
            XCTAssertFalse(fetcherStateFileExists(in: directory))
        }

        let reopenedDatabase = try makeCoreDataDatabase(
            name: "Bookmarks_V6",
            directory: directory,
            modelName: "BookmarksModel",
            preferredBundles: [Bookmarks.bundle, Bundle(for: BookmarkEntity.self)]
        )
        let reopenedMirror = SumiBookmarkMirrorManager(database: reopenedDatabase)

        XCTAssertEqual(reopenedMirror.allHosts(), ["updated-bookmarks.example", "updated-shortcuts.example"])
        XCTAssertEqual(try fetchBookmarkMirrorRecords(in: reopenedDatabase), expectedRecords)
        XCTAssertFalse(fetcherStateFileExists(in: directory))
    }

    func testDDGFetcherStateStorePreservesMissingIDsAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkFaviconFetcherStateParity")
        let missingIDsFileURL = directory
            .appendingPathComponent("FaviconsFetcher", isDirectory: true)
            .appendingPathComponent("missingIDs")
        let ids: Set<String> = [
            "sumi-real-bookmark-alpha",
            "sumi-real-bookmark-beta",
            "sumi-favicon-mirror-11111111-2222-3333-4444-555555555555",
        ]

        let store = try BookmarksFaviconsFetcherStateStore(applicationSupportURL: directory)
        try store.storeBookmarkIDs(ids)

        XCTAssertTrue(FileManager.default.fileExists(atPath: missingIDsFileURL.path))
        XCTAssertEqual(try store.getBookmarkIDs(), ids)
        XCTAssertEqual(try BookmarksFaviconsFetcherStateStore(applicationSupportURL: directory).getBookmarkIDs(), ids)

        try "legacy-one,legacy-two".write(to: missingIDsFileURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try BookmarksFaviconsFetcherStateStore(applicationSupportURL: directory).getBookmarkIDs(),
            ["legacy-one", "legacy-two"]
        )
    }

    func testBookmarkMirrorAttachInitializesFetcherStateWithoutFetchingFavicons() throws {
        let directory = try temporaryDirectory(named: "SumiBookmarkFaviconInitializeNoFetchParity")
        let bookmarkID = "Initialization-Bookmark"
        let expectedMirrorID = "sumi-real-bookmark-\(bookmarkID.lowercased())"
        let didStoreIDs = expectation(description: "Fetcher state was initialized")
        let stateStore = RecordingBookmarksFaviconsFetcherStateStore(didStoreIDs: didStoreIDs)
        let faviconFetcher = RecordingFaviconFetcher()
        let faviconStore = StubSumiFaviconStore()

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
                title: "Initialization Bookmark",
                url: try XCTUnwrap(URL(string: "https://initialization.example/start")),
                folderID: nil
            ),
        ])

        let fetchScheduler = SumiDDGBookmarkFaviconFetchScheduler(
            database: database,
            stateStore: stateStore,
            fetcher: faviconFetcher,
            faviconStore: { faviconStore },
        )
        mirror.attach(fetchScheduler: fetchScheduler)

        wait(for: [didStoreIDs], timeout: 2.0)

        XCTAssertEqual(stateStore.storedBookmarkIDs, [expectedMirrorID])
        XCTAssertEqual(faviconFetcher.fetchCount, 0)
        XCTAssertFalse(fetcherStateFileExists(in: directory))
    }

    func testDDGBookmarkFaviconStoreAdapterForwardsToSumiStorage() async throws {
        let storage = RecordingSumiFaviconStore()
        let adapter = SumiDDGBookmarkFaviconStoringAdapter(storage: storage)
        let imageData = Data([0x01, 0x02, 0x03])
        let faviconURL = try XCTUnwrap(URL(string: "https://assets.example/favicon.ico"))
        let documentURL = try XCTUnwrap(URL(string: "https://adapter.example/start"))

        storage.hasFaviconResult = true

        XCTAssertTrue(adapter.hasFavicon(for: "adapter.example"))

        try await adapter.storeFavicon(imageData, with: faviconURL, for: documentURL)

        XCTAssertEqual(storage.queriedDomains, ["adapter.example"])
        XCTAssertEqual(storage.storedImageData, imageData)
        XCTAssertEqual(storage.storedFaviconURL, faviconURL)
        XCTAssertEqual(storage.storedDocumentURL, documentURL)
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
    ) throws -> SumiDDGCoreDataDatabase {
        if modelName == "Favicons" {
            FaviconValueTransformers.register()
        }
        let model = try XCTUnwrap(loadModel(named: modelName, preferredBundles: preferredBundles))
        let database = SumiDDGCoreDataDatabase(name: name, containerLocation: directory, model: model)
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
            if let model = SumiDDGCoreDataDatabase.loadModel(from: bundle, named: modelName) {
                return model
            }
        }
        return nil
    }

    private func fetchBookmarkMirrorRecords(in database: any SumiCoreDataDatabase) throws -> [BookmarkMirrorRecord] {
        let context = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiBookmarkFaviconMirrorParityRead"
        )
        return try context.performAndWait {
            let request = BookmarkEntity.fetchRequest()
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "%K BEGINSWITH %@", #keyPath(BookmarkEntity.uuid), "sumi-favicon-mirror-"),
                NSPredicate(format: "%K BEGINSWITH %@", #keyPath(BookmarkEntity.uuid), "sumi-real-bookmark-"),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BookmarkEntity.uuid), ascending: true)]
            request.returnsObjectsAsFaults = false
            return try context.fetch(request).map {
                BookmarkMirrorRecord(
                    uuid: $0.uuid ?? "",
                    title: $0.title ?? "",
                    url: $0.url ?? "",
                    parentID: $0.parent?.uuid
                )
            }
        }
    }

    private func fetcherStateFileExists(in directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory
                .appendingPathComponent("FaviconsFetcher", isDirectory: true)
                .appendingPathComponent("missingIDs")
                .path
        )
    }
}

private struct BookmarkMirrorRecord: Equatable {
    let uuid: String
    let title: String
    let url: String
    let parentID: String?
}

private final class RecordingBookmarksFaviconsFetcherStateStore: BookmarksFaviconsFetcherStateStoring {
    private let lock = NSLock()
    private let didStoreIDs: XCTestExpectation
    private var ids = Set<String>()

    var storedBookmarkIDs: Set<String> {
        lock.withLock {
            ids
        }
    }

    init(didStoreIDs: XCTestExpectation) {
        self.didStoreIDs = didStoreIDs
    }

    func getBookmarkIDs() throws -> Set<String> {
        lock.withLock {
            ids
        }
    }

    func storeBookmarkIDs(_ ids: Set<String>) throws {
        lock.withLock {
            self.ids = ids
        }
        didStoreIDs.fulfill()
    }
}

private final class RecordingFaviconFetcher: FaviconFetching {
    private let lock = NSLock()
    private var count = 0

    var fetchCount: Int {
        lock.withLock {
            count
        }
    }

    func fetchFavicon(for url: URL) async throws -> (Data?, URL?) {
        lock.withLock {
            count += 1
        }
        return (nil, nil)
    }
}

@MainActor
private final class StubSumiFaviconStore: SumiFaviconStoring {
    func hasFavicon(for domain: String) -> Bool {
        false
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {}
}

@MainActor
private final class RecordingSumiFaviconStore: SumiFaviconStoring {
    var hasFaviconResult = false
    private(set) var queriedDomains = [String]()
    private(set) var storedImageData: Data?
    private(set) var storedFaviconURL: URL?
    private(set) var storedDocumentURL: URL?

    func hasFavicon(for domain: String) -> Bool {
        queriedDomains.append(domain)
        return hasFaviconResult
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
        storedImageData = imageData
        storedFaviconURL = url
        storedDocumentURL = documentURL
    }
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

    func testFaviconDatabaseContextsShareCoordinatorAndTemporaryStoreURL() throws {
        let directory = try temporaryDirectory(named: "SumiFaviconCoordinatorParity")
        let database = try makeCoreDataDatabase(
            name: "Favicons",
            directory: directory,
            modelName: "Favicons",
            preferredBundles: [.main]
        )

        let firstContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiFaviconCoordinatorParityFirst"
        )
        let secondContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiFaviconCoordinatorParitySecond"
        )

        let firstCoordinator = try XCTUnwrap(firstContext.persistentStoreCoordinator)
        let secondCoordinator = try XCTUnwrap(secondContext.persistentStoreCoordinator)
        let storeURL = try XCTUnwrap(firstCoordinator.persistentStores.first?.url)

        XCTAssertTrue(firstCoordinator === secondCoordinator)
        XCTAssertEqual(firstContext.name, "SumiFaviconCoordinatorParityFirst")
        XCTAssertEqual(secondContext.name, "SumiFaviconCoordinatorParitySecond")
        XCTAssertEqual(storeURL.standardizedFileURL, directory.appendingPathComponent("Favicons.sqlite").standardizedFileURL)
        XCTAssertTrue(storeURL.path.hasPrefix(directory.path))
        XCTAssertFalse(storeURL.path.hasPrefix(applicationSupportDirectory().path))
    }

    func testFaviconStoreClearAllBatchDeleteMergesCurrentContextAndSurvivesReopen() async throws {
        let directory = try temporaryDirectory(named: "SumiFaviconClearAllParity")
        let faviconURL = try XCTUnwrap(URL(string: "https://assets.example/favicon.ico"))
        let documentURL = try XCTUnwrap(URL(string: "https://clear-all.example/start"))
        let dateCreated = try XCTUnwrap(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 2,
            day: 3,
            hour: 4,
            minute: 5,
            second: 6
        ).date)
        let database = try makeCoreDataDatabase(
            name: "Favicons",
            directory: directory,
            modelName: "Favicons",
            preferredBundles: [.main]
        )
        let store = FaviconStore(database: database)

        try await store.save([
            Favicon(
                identifier: try XCTUnwrap(UUID(uuidString: "dddddddd-eeee-ffff-aaaa-bbbbbbbbbbbb")),
                url: faviconURL,
                image: nil,
                relation: .favicon,
                documentUrl: documentURL,
                dateCreated: dateCreated
            ),
        ])
        try await store.save(hostReference: FaviconHostReference(
            identifier: try XCTUnwrap(UUID(uuidString: "eeeeeeee-ffff-aaaa-bbbb-cccccccccccc")),
            smallFaviconUrl: faviconURL,
            mediumFaviconUrl: nil,
            host: "clear-all.example",
            documentUrl: documentURL,
            dateCreated: dateCreated
        ))
        try await store.save(urlReference: FaviconUrlReference(
            identifier: try XCTUnwrap(UUID(uuidString: "ffffffff-aaaa-bbbb-cccc-dddddddddddd")),
            smallFaviconUrl: faviconURL,
            mediumFaviconUrl: nil,
            documentUrl: documentURL,
            dateCreated: dateCreated
        ))

        let faviconsBeforeDelete = try await store.loadFavicons()
        XCTAssertEqual(faviconsBeforeDelete.count, 1)
        let referencesBeforeDelete = try await store.loadFaviconReferences()
        XCTAssertEqual(referencesBeforeDelete.0.count, 1)
        XCTAssertEqual(referencesBeforeDelete.1.count, 1)

        try await store.clearAll()

        let faviconsAfterDelete = try await store.loadFavicons()
        XCTAssertTrue(faviconsAfterDelete.isEmpty)
        let referencesAfterDelete = try await store.loadFaviconReferences()
        XCTAssertTrue(referencesAfterDelete.0.isEmpty)
        XCTAssertTrue(referencesAfterDelete.1.isEmpty)

        let reopenedDatabase = try makeCoreDataDatabase(
            name: "Favicons",
            directory: directory,
            modelName: "Favicons",
            preferredBundles: [.main]
        )
        let reopenedStore = FaviconStore(database: reopenedDatabase)

        let reopenedFavicons = try await reopenedStore.loadFavicons()
        XCTAssertTrue(reopenedFavicons.isEmpty)
        let reopenedReferences = try await reopenedStore.loadFaviconReferences()
        XCTAssertTrue(reopenedReferences.0.isEmpty)
        XCTAssertTrue(reopenedReferences.1.isEmpty)
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
    ) throws -> SumiDDGCoreDataDatabase {
        if modelName == "Favicons" {
            FaviconValueTransformers.register()
        }
        let model = try XCTUnwrap(loadModel(named: modelName, preferredBundles: preferredBundles))
        let database = SumiDDGCoreDataDatabase(name: name, containerLocation: directory, model: model)
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
            if let model = SumiDDGCoreDataDatabase.loadModel(from: bundle, named: modelName) {
                return model
            }
        }
        return nil
    }

    private func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
}
