import CoreData
import Foundation

protocol SumiCoreDataDatabase: AnyObject {
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
}
