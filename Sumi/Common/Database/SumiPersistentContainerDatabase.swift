//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//
import CoreData
import Foundation

/// Owns an `NSPersistentContainer` behind the `SumiCoreDataDatabase`
/// contract: a named SQLite store in a caller-provided directory, with
/// contexts vended only after the store finished loading.
final class SumiPersistentContainerDatabase: SumiCoreDataDatabase {
    enum StoreError: Swift.Error {
        case containerLocationCouldNotBePrepared(underlyingError: Swift.Error)
    }

    private let containerLocation: URL
    private let container: NSPersistentContainer
    private let storeLoaded = DispatchGroup()

    init(
        name: String,
        containerLocation: URL,
        model: NSManagedObjectModel,
        readOnly: Bool = false,
        options: [String: NSObject] = [:]
    ) {
        self.container = NSPersistentContainer(name: name, managedObjectModel: model)
        self.containerLocation = containerLocation

        let description = NSPersistentStoreDescription(
            url: containerLocation.appendingPathComponent("\(name).sqlite")
        )
        description.type = NSSQLiteStoreType
        description.isReadOnly = readOnly
        for (key, value) in options {
            description.setOption(value, forKey: key)
        }
        container.persistentStoreDescriptions = [description]

        storeLoaded.enter()
    }

    func loadStore(completion: @escaping @Sendable (NSManagedObjectContext?, Error?) -> Void) {
        do {
            try FileManager.default.createDirectory(at: containerLocation, withIntermediateDirectories: true)
        } catch {
            storeLoaded.leave()
            completion(nil, StoreError.containerLocationCouldNotBePrepared(underlyingError: error))
            return
        }

        container.loadPersistentStores { [container, storeLoaded] _, error in
            if let error {
                storeLoaded.leave()
                completion(nil, error)
                return
            }

            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = container.persistentStoreCoordinator
            context.name = "Migration"
            context.performAndWait {
                completion(context, nil)
                storeLoaded.leave()
            }
        }
    }

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType,
        name: String?
    ) -> NSManagedObjectContext {
        storeLoaded.wait()

        let context = NSManagedObjectContext(concurrencyType: concurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.name = name
        return context
    }

    static func loadModel(from bundle: Bundle, named name: String) -> NSManagedObjectModel? {
        guard let momdUrl = bundle.url(forResource: name, withExtension: "momd") else { return nil }
        return NSManagedObjectModel(contentsOf: momdUrl)
    }
}
