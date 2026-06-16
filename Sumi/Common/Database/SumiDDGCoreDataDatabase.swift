import CoreData
import Foundation
import Persistence

final class SumiDDGCoreDataDatabase: SumiCoreDataDatabase {
    let ddgDatabase: CoreDataDatabase

    init(
        name: String,
        containerLocation: URL,
        model: NSManagedObjectModel,
        readOnly: Bool = false,
        options: [String: NSObject] = [:]
    ) {
        self.ddgDatabase = CoreDataDatabase(
            name: name,
            containerLocation: containerLocation,
            model: model,
            readOnly: readOnly,
            options: options
        )
    }

    func loadStore(completion: @escaping (NSManagedObjectContext?, Error?) -> Void = { _, _ in }) {
        ddgDatabase.loadStore(completion: completion)
    }

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType,
        name: String?
    ) -> NSManagedObjectContext {
        ddgDatabase.makeContext(concurrencyType: concurrencyType, name: name)
    }

    static func loadModel(from bundle: Bundle, named name: String) -> NSManagedObjectModel? {
        CoreDataDatabase.loadModel(from: bundle, named: name)
    }
}
