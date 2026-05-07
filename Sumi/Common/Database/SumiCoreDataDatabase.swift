import CoreData
import Foundation

protocol SumiCoreDataDatabase: AnyObject {
    var name: String { get }
    var containerLocation: URL { get }
    var storeURL: URL { get }

    func loadStore(completion: @escaping (NSManagedObjectContext?, Error?) -> Void)
    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType,
        name: String?
    ) -> NSManagedObjectContext
}

extension SumiCoreDataDatabase {
    func loadStore() {
        loadStore { _, _ in }
    }

    func makeContext(
        concurrencyType: NSManagedObjectContextConcurrencyType
    ) -> NSManagedObjectContext {
        makeContext(concurrencyType: concurrencyType, name: nil)
    }
}
