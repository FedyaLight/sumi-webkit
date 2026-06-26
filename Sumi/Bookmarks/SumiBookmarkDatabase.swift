import Bookmarks
import CoreData
import Foundation
import OSLog

final class SumiBookmarkDatabase {
    private static let log = Logger.sumi(category: "BookmarkDatabase")

    private let database: (any SumiCoreDataDatabase)?
    let unavailableReason: SumiBookmarkDatabaseUnavailableReason?

    var isAvailable: Bool {
        unavailableReason == nil
    }

    init(directory: URL? = nil) {
        let directory = directory ?? Self.defaultDirectoryURL()
        guard let model = Self.loadBookmarksModel() else {
            let reason = SumiBookmarkDatabaseUnavailableReason.missingModel("BookmarksModel")
            Self.log.fault("\(reason.description, privacy: .public)")
            self.database = nil
            self.unavailableReason = reason
            return
        }

        let database = SumiDDGCoreDataDatabase(
            name: "SumiBookmarks",
            containerLocation: directory,
            model: model
        )
        self.database = database
        self.unavailableReason = nil
        database.loadStore()
        prepareFolderStructure()
    }

    #if DEBUG
        init(unavailableReason: SumiBookmarkDatabaseUnavailableReason) {
            self.database = nil
            self.unavailableReason = unavailableReason
        }
    #endif

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType,
        name: String
    ) -> NSManagedObjectContext {
        guard let database else {
            preconditionFailure(
                "Sumi bookmarks database context requested while unavailable: \(unavailableReason?.description ?? "unknown reason")"
            )
        }

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
                do {
                    try context.save()
                } catch {
                    context.rollback()
                    Self.log.error(
                        "Failed to save bookmark bootstrap folder structure: \(String(describing: error), privacy: .public)"
                    )
                }
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

        let directory = SumiApplicationSupportDirectory.appRootURL()
            .appendingPathComponent("Bookmarks", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            log.error(
                "Failed to create bookmarks directory: \(String(describing: error), privacy: .public)"
            )
        }
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

enum SumiBookmarkDatabaseUnavailableReason: Error, CustomStringConvertible, Equatable, Sendable {
    case missingModel(String)

    var description: String {
        switch self {
        case .missingModel(let name):
            return "Sumi bookmarks database is unavailable because \(name) could not be loaded."
        }
    }
}
