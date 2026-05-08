//
//  CoreDataStore.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreData
import Foundation

extension NSManagedObject {
    class func entityClassName() -> String {
        String(describing: self)
    }
}

protocol ValueRepresentableManagedObject: NSManagedObject {
    associatedtype ValueType

    func valueRepresentation() -> ValueType?
    func update(with value: ValueType) throws
}

enum CoreDataStoreError: Error, Equatable {
    case objectNotFound
    case invalidManagedObject
}

extension CoreDataStore {

    func add(_ value: Value) throws -> NSManagedObjectID {
        try add([value]).first?.id ?? { throw CoreDataStoreError.objectNotFound }()
    }

}

internal class CoreDataStore<ManagedObject: ValueRepresentableManagedObject> {

    private var readContext: NSManagedObjectContext?

    private func writeContext() -> NSManagedObjectContext? {
        guard let context = readContext else { return nil }

        let newContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        newContext.persistentStoreCoordinator = context.persistentStoreCoordinator
        newContext.name = context.name

        return newContext
    }

    convenience init(database: (any SumiCoreDataDatabase)?, tableName: String) {
        self.init(context: database?.makeContext(concurrencyType: .privateQueueConcurrencyType, name: tableName))
    }

    init(context: NSManagedObjectContext?) {
        readContext = context
    }

    typealias Value = ManagedObject.ValueType
    typealias IDValueTuple = (id: NSManagedObjectID, value: Value)

    func load<Result>(objectsWithPredicate predicate: NSPredicate? = nil,
                      sortDescriptors: [NSSortDescriptor]? = nil,
                      into initialResult: Result,
                      _ accumulate: (inout Result, IDValueTuple) throws -> Void) throws -> Result {

        guard let context = readContext else { return initialResult }
        return try context.performAndWait {
            let fetchRequest = NSFetchRequest<ManagedObject>(entityName: ManagedObject.entityClassName())
            fetchRequest.predicate = predicate
            fetchRequest.sortDescriptors = sortDescriptors
            fetchRequest.returnsObjectsAsFaults = false

            return try context.fetch(fetchRequest).reduce(into: initialResult) { result, managedObject in
                guard let value = managedObject.valueRepresentation() else { return }
                try accumulate(&result, (managedObject.objectID, value))
            }
        }
    }

    func add<S: Sequence>(_ values: S) throws -> [(value: Value, id: NSManagedObjectID)] where S.Element == Value {
        guard let context = writeContext() else { return [] }

        return try context.performAndWait { [context] in
            let entityName = ManagedObject.entityClassName()
            var added = [(Value, NSManagedObject)]()
            added.reserveCapacity(values.underestimatedCount)

            for value in values {
                guard let managedObject = NSEntityDescription
                        .insertNewObject(forEntityName: entityName, into: context) as? ManagedObject
                else {
                    throw CoreDataStoreError.invalidManagedObject
                }

                try managedObject.update(with: value)
                added.append((value, managedObject))
            }

            try context.save()
            return added.map { ($0, $1.objectID) }
        }
    }

    func remove(objectWithId id: NSManagedObjectID, completionHandler: (@Sendable (Error?) -> Void)?) {
        guard let context = writeContext() else { return }
        @Sendable func mainQueueCompletion(error: Error?) {
            guard completionHandler != nil else { return }
            DispatchQueue.main.async {
                completionHandler?(error)
            }
        }

        context.perform { [context] in
            do {
                guard let managedObject = try? context.existingObject(with: id) else {
                    assertionFailure("CoreDataStore: Failed to get Managed Object from the context")
                    throw CoreDataStoreError.objectNotFound
                }

                context.delete(managedObject)

                try context.save()
                mainQueueCompletion(error: nil)
            } catch {
                assertionFailure("CoreDataStore: Saving of context failed")
                mainQueueCompletion(error: error)
            }
        }
    }

}
