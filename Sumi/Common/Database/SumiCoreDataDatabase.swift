import CoreData
import Foundation

protocol SumiCoreDataDatabase: AnyObject {
    /// The completion may run on the persistent container's loading queue,
    /// so it must be Sendable.
    func loadStore(completion: @escaping @Sendable (NSManagedObjectContext?, Error?) -> Void)
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
