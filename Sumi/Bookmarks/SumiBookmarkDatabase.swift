import Bookmarks
import CoreData
import Foundation

final class SumiBookmarkDatabase {
    private let database: any SumiCoreDataDatabase

    init(directory: URL? = nil) {
        let directory = directory ?? Self.defaultDirectoryURL()
        guard let model = Self.loadBookmarksModel() else {
            fatalError("Failed to load BookmarksModel")
        }

        database = SumiDDGCoreDataDatabase(
            name: "SumiBookmarks",
            containerLocation: directory,
            model: model
        )
        database.loadStore()
        prepareFolderStructure()
    }

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType,
        name: String
    ) -> NSManagedObjectContext {
        let context = database.makeContext(
            concurrencyType: concurrencyType,
            name: name
        )
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return context
    }

    private func prepareFolderStructure() {
        let context = makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiBookmarksBootstrap"
        )
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            if context.hasChanges {
                try? context.save()
            }
        }
    }

    private static func defaultDirectoryURL() -> URL {
        if RuntimeDiagnostics.isRunningTests {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent(
                    "SumiBookmarks-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }

        if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
           !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
                .appendingPathComponent("Bookmarks", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: overrideURL,
                withIntermediateDirectories: true
            )
            return overrideURL
        }

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = appSupport
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Bookmarks", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func loadBookmarksModel() -> NSManagedObjectModel? {
        let candidateBundles = [
            Bookmarks.bundle,
            Bundle(for: BookmarkEntity.self),
            .main,
        ] + Bundle.allBundles + Bundle.allFrameworks

        var seen = Set<String>()
        for bundle in candidateBundles where seen.insert(bundle.bundleURL.path).inserted {
            if let model = SumiDDGCoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") {
                return model
            }
        }
        return nil
    }
}
