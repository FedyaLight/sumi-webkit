import AppKit
import Bookmarks
import CoreData
import Foundation
import WebKit

enum SumiFaviconLookupKey {
    static func cacheKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }

        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty
        {
            return host.lowercased()
        }

        let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absoluteString.isEmpty ? nil : absoluteString.lowercased()
    }

    static func documentURL(for key: String) -> URL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitURL = URL(string: trimmed),
           let scheme = explicitURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return explicitURL
        }

        return URL(string: "https://\(trimmed)")
    }
}

@MainActor
protocol BookmarkManager: AnyObject {
    func allHosts() -> Set<String>
}

private enum SumiFaviconPersistence {
    static func rootDirectoryURL() -> URL {
        if RuntimeDiagnostics.isRunningTests {
            let testURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SumiFavicons-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: testURL, withIntermediateDirectories: true)
            return testURL
        }

        if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
           !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            return overrideURL
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleDirectory = appSupport.appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        return bundleDirectory
    }

    static func directory(named component: String) -> URL {
        let directory = rootDirectoryURL().appendingPathComponent(component, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

@MainActor
final class SumiBookmarkMirrorManager: BookmarkManager {
    private let database: any SumiCoreDataDatabase
    private var fetchScheduler: (any SumiBookmarkFaviconFetchScheduling)?
    nonisolated private static let mirrorPrefix = "sumi-favicon-mirror-"
    nonisolated private static let realBookmarkPrefix = "sumi-real-bookmark-"
    private var didInitializeFetcherState = false

    init(database: any SumiCoreDataDatabase) {
        self.database = database
        prepareFolderStructureIfNeeded()
    }

    func attach(fetchScheduler: any SumiBookmarkFaviconFetchScheduling) {
        self.fetchScheduler = fetchScheduler
        initializeFetcherState()
    }

    func initializeFetcherState() {
        guard !didInitializeFetcherState else { return }
        fetchScheduler?.initializeFetcherState()
        didInitializeFetcherState = true
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        let desiredRecords = pins.map {
            DesiredBookmarkRecord(
                uuid: Self.mirrorBookmarkID(for: $0.id),
                title: $0.title,
                urlString: $0.launchURL.absoluteString
            )
        }

        syncDesiredRecords(
            desiredRecords,
            prefix: Self.mirrorPrefix,
            contextName: "SumiFaviconShortcutBookmarksSync"
        )
    }

    func syncBookmarks(_ bookmarks: [SumiBookmark]) {
        let desiredRecords = bookmarks.map {
            DesiredBookmarkRecord(
                uuid: Self.realBookmarkID(for: $0.id),
                title: $0.title,
                urlString: $0.url.absoluteString
            )
        }

        syncDesiredRecords(
            desiredRecords,
            prefix: Self.realBookmarkPrefix,
            contextName: "SumiFaviconRealBookmarksSync"
        )
    }

    private func syncDesiredRecords(
        _ desiredRecords: [DesiredBookmarkRecord],
        prefix: String,
        contextName: String
    ) {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: contextName)

        let (modifiedIDs, deletedIDs) = context.performAndWait {
            var modifiedIDs = Set<String>()
            var deletedIDs = Set<String>()

            BookmarkUtils.prepareFoldersStructure(in: context)
            guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else {
                return (modifiedIDs, deletedIDs)
            }

            let existingMirrorBookmarks = Self.fetchMirrorBookmarks(in: context, prefix: prefix)
            let existingPairs: [(String, BookmarkEntity)] = existingMirrorBookmarks.compactMap { bookmark in
                guard let uuid = bookmark.uuid else { return nil }
                return (uuid, bookmark)
            }
            let existingByUUID = Dictionary(uniqueKeysWithValues: existingPairs)

            let desiredPairs = desiredRecords.map { ($0.uuid, $0) }
            let desiredByUUID = Dictionary(uniqueKeysWithValues: desiredPairs)

            for (uuid, bookmark) in existingByUUID where desiredByUUID[uuid] == nil {
                deletedIDs.insert(uuid)
                context.delete(bookmark)
            }

            for (uuid, record) in desiredByUUID {
                if let existing = existingByUUID[uuid] {
                    let expectedURL = record.urlString
                    let expectedTitle = record.title
                    if existing.url != expectedURL || existing.title != expectedTitle || existing.parent == nil {
                        existing.url = expectedURL
                        existing.title = expectedTitle
                        if existing.parent == nil {
                            rootFolder.addToChildren(existing)
                        }
                        modifiedIDs.insert(uuid)
                    }
                } else {
                    let bookmark = BookmarkEntity.makeBookmark(
                        title: record.title,
                        url: record.urlString,
                        parent: rootFolder,
                        context: context
                    )
                    bookmark.uuid = uuid
                    modifiedIDs.insert(uuid)
                }
            }

            guard context.hasChanges else { return (modifiedIDs, deletedIDs) }
            try? context.save()
            return (modifiedIDs, deletedIDs)
        }

        guard let fetchScheduler else { return }
        if !didInitializeFetcherState {
            fetchScheduler.initializeFetcherState()
            didInitializeFetcherState = true
        }
        if !modifiedIDs.isEmpty || !deletedIDs.isEmpty {
            fetchScheduler.updateBookmarkIDs(modified: modifiedIDs, deleted: deletedIDs)
            Task {
                await fetchScheduler.startFetching()
            }
        }
    }

    func allHosts() -> Set<String> {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "SumiFaviconBookmarksHosts")
        return context.performAndWait {
            var hosts = Set<String>()
            for bookmark in Self.fetchMirrorBookmarks(in: context, prefixes: [Self.mirrorPrefix, Self.realBookmarkPrefix]) {
                guard let urlString = bookmark.url,
                      let url = URL(string: urlString),
                      let host = url.host
                else {
                    continue
                }
                hosts.insert(host)
            }
            return hosts
        }
    }

    private func prepareFolderStructureIfNeeded() {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "SumiFaviconBookmarksBootstrap")
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            if context.hasChanges {
                try? context.save()
            }
        }
    }

    private struct DesiredBookmarkRecord: Sendable {
        let uuid: String
        let title: String
        let urlString: String
    }

    nonisolated private static func mirrorBookmarkID(for pinID: UUID) -> String {
        mirrorPrefix + pinID.uuidString.lowercased()
    }

    nonisolated private static func realBookmarkID(for bookmarkID: String) -> String {
        realBookmarkPrefix + bookmarkID.lowercased()
    }

    nonisolated private static func fetchMirrorBookmarks(in context: NSManagedObjectContext, prefix: String) -> [BookmarkEntity] {
        fetchMirrorBookmarks(in: context, prefixes: [prefix])
    }

    nonisolated private static func fetchMirrorBookmarks(in context: NSManagedObjectContext, prefixes: [String]) -> [BookmarkEntity] {
        let prefixPredicates = prefixes.map {
            NSPredicate(format: "%K BEGINSWITH %@", #keyPath(BookmarkEntity.uuid), $0)
        }
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSCompoundPredicate(orPredicateWithSubpredicates: prefixPredicates),
                NSPredicate(
                    format: "%K == NO AND (%K == NO OR %K == nil)",
                    #keyPath(BookmarkEntity.isPendingDeletion),
                    #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
                ),
            ]
        )
        request.returnsObjectsAsFaults = false
        return (try? context.fetch(request)) ?? []
    }
}

@MainActor
final class SumiFaviconSystem {
    static let shared = SumiFaviconSystem()

    let manager: FaviconManager
    let bookmarkMirror: any SumiFaviconMirrorSyncing

    private let faviconDatabase: SumiDDGCoreDataDatabase
    private let bookmarkDatabase: SumiDDGCoreDataDatabase

    private init() {
        let rootDirectoryURL = SumiFaviconPersistence.directory(named: "Favicons/DDGBackend-v2")
        let privacyConfigurationManager = SumiContentBlockingPrivacyConfigurationManager(
            isContentBlockingEnabled: false
        )

        faviconDatabase = Self.makeDatabase(
            name: "Favicons",
            directory: rootDirectoryURL.appendingPathComponent("Cache", isDirectory: true),
            modelName: "Favicons",
            bundle: .main
        )
        bookmarkDatabase = Self.makeDatabase(
            name: "Bookmarks_V6",
            directory: rootDirectoryURL.appendingPathComponent("Bookmarks", isDirectory: true),
            modelName: "BookmarksModel",
            bundle: Bundle(for: BookmarkEntity.self)
        )

        let ddgBookmarkMirror = SumiDDGBookmarkFaviconMirror(database: bookmarkDatabase)
        manager = FaviconManager(
            cacheType: .standard(faviconDatabase),
            bookmarkManager: ddgBookmarkMirror,
            privacyConfigurationManager: privacyConfigurationManager
        )
        do {
            try ddgBookmarkMirror.attachDDGFetcher(
                applicationSupportURL: rootDirectoryURL,
                faviconStore: { [manager] in manager }
            )
        } catch {
            fatalError("Failed to initialize favicon bookmark mirror fetcher: \(error)")
        }
        bookmarkMirror = ddgBookmarkMirror
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        bookmarkMirror.syncShortcutPins(pins)
    }

    func syncBookmarks(_ bookmarks: [SumiBookmark]) {
        bookmarkMirror.syncBookmarks(bookmarks)
    }

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        _ = await manager.burn(
            bookmarkManager: bookmarkMirror,
            savedLogins: savedLogins
        )
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        _ = await manager.burnDomains(
            domains,
            exceptBookmarks: bookmarkMirror,
            exceptSavedLogins: savedLogins,
            exceptExistingHistoryHosts: remainingHistoryHosts,
            registrableDomainResolver: SumiRegistrableDomainResolver()
        )
    }

    private static func makeDatabase(
        name: String,
        directory: URL,
        modelName: String,
        bundle: Bundle
    ) -> SumiDDGCoreDataDatabase {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FaviconValueTransformers.register()
        guard let model = Self.loadModel(named: modelName, preferredBundle: bundle) else {
            fatalError("Failed to load Core Data model \(modelName)")
        }

        let database = SumiDDGCoreDataDatabase(name: name, containerLocation: directory, model: model)
        database.loadStore()
        return database
    }

    private static func loadModel(named modelName: String, preferredBundle: Bundle) -> NSManagedObjectModel? {
        let bundles = ([preferredBundle, .main] + Bundle.allBundles + Bundle.allFrameworks + bundledResourceBundles())
            .reduce(into: [String: Bundle]()) { result, bundle in
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

    private static func bundledResourceBundles() -> [Bundle] {
        let resourceRoots = (Bundle.allBundles + [.main]).compactMap(\.resourceURL)
        var bundles = [Bundle]()
        for resourceRoot in resourceRoots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: resourceRoot,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for url in urls where url.pathExtension == "bundle" {
                if let bundle = Bundle(url: url) {
                    bundles.append(bundle)
                }
            }
        }
        return bundles
    }
}
