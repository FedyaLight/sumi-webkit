import AppKit
import Bookmarks
import BrowserServicesKit
import Combine
import Common
import CoreData
import Foundation
import History
import Persistence
import PrivacyConfig
import UserScript
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

struct SumiStaticPrivacyConfiguration: PrivacyConfiguration {
    let identifier = "sumi-favicon-static"
    let version: String? = nil
    let userUnprotectedDomains: [String] = []
    let tempUnprotectedDomains: [String] = []
    let trackerAllowlist = PrivacyConfigurationData.TrackerAllowlist(entries: [:], state: PrivacyConfigurationData.State.disabled)

    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool {
        defaultValue
    }

    func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        .disabled(.featureMissing)
    }

    func isSubfeatureEnabled(
        _ subfeature: any PrivacySubfeature,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double,
        defaultValue: Bool
    ) -> Bool {
        defaultValue
    }

    func stateFor(
        _ subfeature: any PrivacySubfeature,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double
    ) -> PrivacyConfigurationFeatureState {
        .disabled(.featureMissing)
    }

    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] { [] }
    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool { true }
    func isProtected(domain: String?) -> Bool { true }
    func isUserUnprotected(domain: String?) -> Bool { false }
    func isTempUnprotected(domain: String?) -> Bool { false }
    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool { false }
    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings { [:] }
    func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? { nil }
    func userEnabledProtection(forDomain: String) {}
    func userDisabledProtection(forDomain: String) {}

    func stateFor(
        subfeatureID: SubfeatureID,
        parentFeatureID: ParentFeatureID,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double
    ) -> PrivacyConfigurationFeatureState {
        .disabled(.featureMissing)
    }

    func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? { nil }
    func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? { nil }
}

final class SumiStaticInternalUserDecider: InternalUserDecider {
    let isInternalUser = false
    var isInternalUserPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    @discardableResult
    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        _ = url
        _ = response
        return false
    }
}

final class SumiStaticPrivacyConfigurationManager: PrivacyConfigurationManaging {
    let currentConfig = Data("{}".utf8)
    var updatesPublisher: AnyPublisher<Void, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }
    let privacyConfig: PrivacyConfiguration = SumiStaticPrivacyConfiguration()
    let internalUserDecider: InternalUserDecider = SumiStaticInternalUserDecider()

    @discardableResult
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        _ = etag
        _ = data
        return .embedded
    }
}

@MainActor
final class SumiBookmarkMirrorManager: BookmarkManager {
    private let database: CoreDataDatabase
    private let rootDirectoryURL: URL
    private weak var faviconsFetcher: BookmarksFaviconsFetcher?
    nonisolated private static let mirrorPrefix = "sumi-favicon-mirror-"
    private var didInitializeFetcherState = false

    init(database: CoreDataDatabase, rootDirectoryURL: URL) {
        self.database = database
        self.rootDirectoryURL = rootDirectoryURL
        prepareFolderStructureIfNeeded()
    }

    func attach(fetcher: BookmarksFaviconsFetcher) {
        faviconsFetcher = fetcher
        guard !didInitializeFetcherState else { return }
        fetcher.initializeFetcherState()
        didInitializeFetcherState = true
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "SumiFaviconBookmarksSync")
        var modifiedIDs = Set<String>()
        var deletedIDs = Set<String>()
        let desiredRecords = pins.map {
            DesiredBookmarkRecord(
                uuid: Self.mirrorBookmarkID(for: $0.id),
                title: $0.title,
                urlString: $0.launchURL.absoluteString
            )
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else { return }

            let existingMirrorBookmarks = Self.fetchMirrorBookmarks(in: context, prefix: Self.mirrorPrefix)
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

            guard context.hasChanges else { return }
            try? context.save()
        }

        guard let faviconsFetcher else { return }
        if !didInitializeFetcherState {
            faviconsFetcher.initializeFetcherState()
            didInitializeFetcherState = true
        }
        if !modifiedIDs.isEmpty || !deletedIDs.isEmpty {
            faviconsFetcher.updateBookmarkIDs(modified: modifiedIDs, deleted: deletedIDs)
            Task {
                await faviconsFetcher.startFetching()
            }
        }
    }

    func clearMirror() {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "SumiFaviconBookmarksClear")
        var deletedIDs = Set<String>()

        context.performAndWait {
            let bookmarks = Self.fetchMirrorBookmarks(in: context, prefix: Self.mirrorPrefix)
            for bookmark in bookmarks {
                if let uuid = bookmark.uuid {
                    deletedIDs.insert(uuid)
                }
                context.delete(bookmark)
            }
            if context.hasChanges {
                try? context.save()
            }
        }

        guard let faviconsFetcher, !deletedIDs.isEmpty else { return }
        faviconsFetcher.updateBookmarkIDs(modified: [], deleted: deletedIDs)
    }

    func allHosts() -> Set<String> {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "SumiFaviconBookmarksHosts")
        var hosts = Set<String>()
        context.performAndWait {
            for bookmark in Self.fetchMirrorBookmarks(in: context, prefix: Self.mirrorPrefix) {
                guard let urlString = bookmark.url,
                      let url = URL(string: urlString),
                      let host = url.host
                else {
                    continue
                }
                hosts.insert(host)
            }
        }
        return hosts
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

    nonisolated private static func fetchMirrorBookmarks(in context: NSManagedObjectContext, prefix: String) -> [BookmarkEntity] {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K BEGINSWITH %@ AND %K == NO AND (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.uuid), prefix,
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )
        request.returnsObjectsAsFaults = false
        return (try? context.fetch(request)) ?? []
    }
}

@MainActor
final class SumiFaviconSystem {
    static let shared = SumiFaviconSystem()

    let manager: FaviconManager
    let bookmarkMirror: SumiBookmarkMirrorManager
    let fireproofDomains: FireproofDomains

    private let rootDirectoryURL: URL
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let faviconDatabase: CoreDataDatabase
    private let bookmarkDatabase: CoreDataDatabase
    private let fireproofDatabase: CoreDataDatabase
    private let bookmarksFaviconsFetcher: BookmarksFaviconsFetcher

    private init() {
        rootDirectoryURL = SumiFaviconPersistence.directory(named: "Favicons/DDGBackend-v2")
        privacyConfigurationManager = SumiStaticPrivacyConfigurationManager()

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
        fireproofDatabase = Self.makeDatabase(
            name: "Permissions",
            directory: rootDirectoryURL.appendingPathComponent("Fireproof", isDirectory: true),
            modelName: "FireproofDomains",
            bundle: .main
        )

        bookmarkMirror = SumiBookmarkMirrorManager(
            database: bookmarkDatabase,
            rootDirectoryURL: rootDirectoryURL
        )
        fireproofDomains = FireproofDomains(
            store: FireproofDomainsStore(database: fireproofDatabase, tableName: "FireproofDomains"),
            tld: TLD()
        )
        manager = FaviconManager(
            cacheType: .standard(faviconDatabase),
            bookmarkManager: bookmarkMirror,
            fireproofDomains: fireproofDomains,
            privacyConfigurationManager: privacyConfigurationManager
        )

        let stateStore: BookmarksFaviconsFetcherStateStore
        do {
            stateStore = try BookmarksFaviconsFetcherStateStore(applicationSupportURL: rootDirectoryURL)
        } catch {
            fatalError("Failed to initialize favicon bookmark mirror state store: \(error)")
        }

        bookmarksFaviconsFetcher = BookmarksFaviconsFetcher(
            database: bookmarkDatabase,
            stateStore: stateStore,
            fetcher: FaviconFetcher(),
            faviconStore: { [manager] in manager },
            errorEvents: nil
        )
        bookmarkMirror.attach(fetcher: bookmarksFaviconsFetcher)
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        bookmarkMirror.syncShortcutPins(pins)
    }

    func image(forLookupKey key: String) -> NSImage? {
        guard let documentURL = SumiFaviconLookupKey.documentURL(for: key) else { return nil }
        if let favicon = manager.getCachedFavicon(for: documentURL, sizeCategory: .small, fallBackToSmaller: true) {
            return favicon.image
        }
        if let host = documentURL.host,
           let favicon = manager.getCachedFavicon(for: host, sizeCategory: .small, fallBackToSmaller: true)
        {
            return favicon.image
        }
        return nil
    }

    func cacheStats() -> (count: Int, domains: [String]) {
        let domains = Set(bookmarkMirror.allHosts())
        return (domains.count, Array(domains).sorted())
    }

    func clearAll() {
        manager.clearAll()
        bookmarkMirror.clearMirror()
    }

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        _ = await manager.burn(
            except: fireproofDomains,
            bookmarkManager: bookmarkMirror,
            savedLogins: savedLogins
        )
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistory: BrowsingHistory,
        savedLogins: Set<String>
    ) async {
        _ = await manager.burnDomains(
            domains,
            exceptBookmarks: bookmarkMirror,
            exceptSavedLogins: savedLogins,
            exceptExistingHistory: remainingHistory,
            tld: TLD()
        )
    }

    private static func makeDatabase(
        name: String,
        directory: URL,
        modelName: String,
        bundle: Bundle
    ) -> CoreDataDatabase {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FaviconValueTransformers.register()
        guard let model = Self.loadModel(named: modelName, preferredBundle: bundle) else {
            fatalError("Failed to load Core Data model \(modelName)")
        }

        let database = CoreDataDatabase(name: name, containerLocation: directory, model: model)
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
            if let model = CoreDataDatabase.loadModel(from: bundle, named: modelName) {
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
