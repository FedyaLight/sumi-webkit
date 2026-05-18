//
//  FaviconStore.swift
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

import Cocoa
import CoreData
import Combine
import os.log
import SQLite3

enum FaviconValueTransformers {
    static func register() {
        ValueTransformer.setValueTransformer(
            SecureCodingValueTransformer<NSURL>(),
            forName: NSValueTransformerName("NSURLTransformer")
        )
        ValueTransformer.setValueTransformer(
            SecureCodingValueTransformer<NSString>(),
            forName: NSValueTransformerName("NSStringTransformer")
        )
        ValueTransformer.setValueTransformer(
            SecureCodingValueTransformer<NSImage>(),
            forName: NSValueTransformerName("NSImageTransformer")
        )
    }
}

private final class SecureCodingValueTransformer<T: NSObject & NSSecureCoding>: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let value = value as? T else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
    }
}

protocol FaviconStoring {

    func loadFavicons() async throws -> [Favicon]
    func loadFavicons(with urls: [URL]) async throws -> [Favicon]
    func loadFaviconMetadata() async throws -> [FaviconMetadata]
    func save(_ favicons: [Favicon]) async throws
    func removeFavicons(_ favicons: [Favicon]) async throws
    func removeFavicons(with urls: [URL]) async throws
    func removeFavicons(withIdentifiers identifiers: [UUID]) async throws

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference])
    func save(hostReference: FaviconHostReference) async throws
    func save(urlReference: FaviconUrlReference) async throws
    func remove(hostReferences: [FaviconHostReference]) async throws
    func remove(urlReferences: [FaviconUrlReference]) async throws
    func clearAll() async throws

}

struct FaviconMetadata {
    let identifier: UUID
    let url: URL
    let documentUrl: URL
    let dateCreated: Date
}

final class FaviconStore: FaviconStoring {

    enum FaviconStoreError: Error {
        case savingFailed
    }

    private let context: NSManagedObjectContext
    private let imageStore: FaviconDiskImageStore
    private let storeURL: URL

    init(database: any SumiCoreDataDatabase) {
        storeURL = database.storeURL
        context = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "Favicons")
        imageStore = FaviconDiskImageStore(
            directory: database.storeURL
                .deletingLastPathComponent()
                .appendingPathComponent("FaviconImageData", isDirectory: true)
        )
    }

    func loadFavicons() async throws -> [Favicon] {
        try await loadFavicons(matching: nil)
    }

    func loadFavicons(with urls: [URL]) async throws -> [Favicon] {
        let urls = Array(Set(urls))
        guard !urls.isEmpty else { return [] }

        return try await loadFavicons(matching: urls)
    }

    private func loadFavicons(matching urls: [URL]?) async throws -> [Favicon] {
        try await withCheckedThrowingContinuation { [context, imageStore] continuation in
            context.perform {
                do {
                    let rows = try Self.fetchFaviconRows(in: context, matching: urls)
                    let favicons = try Self.makeFavicons(from: rows, imageStore: imageStore)
                    Logger.favicons.debug("\(favicons.count) favicons loaded")

                    continuation.resume(returning: favicons)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadFaviconMetadata() async throws -> [FaviconMetadata] {
        try await loadFaviconMetadata(matching: nil)
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        let identifiers = favicons.map { $0.identifier }
        return try await removeFavicons(withIdentifiers: identifiers)
    }

    func removeFavicons(with urls: [URL]) async throws {
        let urls = Array(Set(urls))
        guard !urls.isEmpty else { return }

        let metadata = try await loadFaviconMetadata(matching: urls)
        try await removeFavicons(withIdentifiers: metadata.map(\.identifier))
    }

    func removeFavicons(withIdentifiers identifiers: [UUID]) async throws {
        return try await remove(identifiers: identifiers, entityName: FaviconManagedObject.entityClassName())
    }

    func save(_ favicons: [Favicon]) async throws {
        try await withCheckedThrowingContinuation { [context, imageStore] continuation in
            context.perform {
                do {
                    for favicon in favicons {
                        guard let faviconMO = NSEntityDescription
                            .insertNewObject(forEntityName: FaviconManagedObject.entityClassName(), into: context) as? FaviconManagedObject else {
                            assertionFailure("FaviconStore savingFailed")
                            throw FaviconStoreError.savingFailed
                        }
                        if let imageData = Self.encodedImageData(for: favicon) {
                            try imageStore.save(imageData, for: favicon.identifier)
                        }
                        faviconMO.update(favicon: favicon)
                    }

                    try context.save()

                    continuation.resume()

                } catch let error as FaviconStoreError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: FaviconStoreError.savingFailed)
                }
            }
        }
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        try await withCheckedThrowingContinuation { [context] continuation in
            context.perform {
                let hostFetchRequest = FaviconHostReferenceManagedObject.fetchRequest() as NSFetchRequest<FaviconHostReferenceManagedObject>
                hostFetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(FaviconHostReferenceManagedObject.dateCreated), ascending: true)]
                hostFetchRequest.returnsObjectsAsFaults = false
                let faviconHostReferences: [FaviconHostReference]
                do {
                    let faviconHostReferenceMOs = try context.fetch(hostFetchRequest)
                    Logger.favicons.debug("\(faviconHostReferenceMOs.count) favicon host references loaded")
                    faviconHostReferences = faviconHostReferenceMOs.compactMap { FaviconHostReference(faviconHostReferenceMO: $0) }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let urlFetchRequest = FaviconUrlReferenceManagedObject.fetchRequest() as NSFetchRequest<FaviconUrlReferenceManagedObject>
                urlFetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(FaviconUrlReferenceManagedObject.dateCreated), ascending: true)]
                urlFetchRequest.returnsObjectsAsFaults = false
                do {
                    let faviconUrlReferenceMOs = try context.fetch(urlFetchRequest)
                    Logger.favicons.debug("\(faviconUrlReferenceMOs.count) favicon url references loaded")
                    let faviconUrlReferences = faviconUrlReferenceMOs.compactMap { FaviconUrlReference(faviconUrlReferenceMO: $0) }
                    continuation.resume(returning: (faviconHostReferences, faviconUrlReferences))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(hostReference: FaviconHostReference) async throws {
        return try await withCheckedThrowingContinuation { [context] continuation in
            context.perform {

                let insertedObject = NSEntityDescription.insertNewObject(forEntityName: FaviconHostReferenceManagedObject.entityClassName(), into: context)
                guard let faviconHostReferenceMO = insertedObject as? FaviconHostReferenceManagedObject else {
                    continuation.resume(throwing: FaviconStoreError.savingFailed)
                    return
                }
                faviconHostReferenceMO.update(hostReference: hostReference)

                do {
                    try context.save()
                } catch {
                    continuation.resume(throwing: FaviconStoreError.savingFailed)
                    return
                }

                continuation.resume()
            }
        }
    }

    func save(urlReference: FaviconUrlReference) async throws {
        return try await withCheckedThrowingContinuation { [context] continuation in
            context.perform {

                let insertedObject = NSEntityDescription.insertNewObject(forEntityName: FaviconUrlReferenceManagedObject.entityClassName(),
                                                                         into: context)
                guard let faviconUrlReferenceMO = insertedObject as? FaviconUrlReferenceManagedObject else {
                    continuation.resume(throwing: FaviconStoreError.savingFailed)
                    return
                }
                faviconUrlReferenceMO.update(urlReference: urlReference)

                do {
                    try context.save()
                } catch {
                    continuation.resume(throwing: FaviconStoreError.savingFailed)
                    return
                }

                continuation.resume()
            }
        }
    }

    func remove(hostReferences: [FaviconHostReference]) async throws {
        let identifiers = hostReferences.map { $0.identifier }
        return try await remove(identifiers: identifiers, entityName: FaviconHostReferenceManagedObject.entityClassName())
    }

    func remove(urlReferences: [FaviconUrlReference]) async throws {
        let identifiers = urlReferences.map { $0.identifier }
        return try await remove(identifiers: identifiers, entityName: FaviconUrlReferenceManagedObject.entityClassName())
    }

    func clearAll() async throws {
        try await withCheckedThrowingContinuation { [context, imageStore, storeURL] (continuation: CheckedContinuation<Void, Error>) in
            context.perform {
                do {
                    let entityNames = [
                        FaviconManagedObject.entityClassName(),
                        FaviconHostReferenceManagedObject.entityClassName(),
                        FaviconUrlReferenceManagedObject.entityClassName()
                    ]

                    for entityName in entityNames {
                        let deleteRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: deleteRequest)
                        batchDeleteRequest.resultType = .resultTypeObjectIDs
                        let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                        let deletedObjects = result?.result as? [NSManagedObjectID] ?? []
                        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjects]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
                    }

                    if context.hasChanges {
                        try context.save()
                    }
                    try imageStore.clearAll()
                    Self.compactStoreIfUseful(at: storeURL, reason: "clearAll")

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func loadFaviconMetadata(matching urls: [URL]?) async throws -> [FaviconMetadata] {
        try await withCheckedThrowingContinuation { [context] continuation in
            context.perform {
                do {
                    let fetchRequest = NSFetchRequest<NSDictionary>(entityName: FaviconManagedObject.entityClassName())
                    fetchRequest.resultType = .dictionaryResultType
                    fetchRequest.propertiesToFetch = [
                        #keyPath(FaviconManagedObject.identifier),
                        #keyPath(FaviconManagedObject.urlEncrypted),
                        #keyPath(FaviconManagedObject.documentUrlEncrypted),
                        #keyPath(FaviconManagedObject.dateCreated),
                    ]
                    if let urls, !urls.isEmpty {
                        fetchRequest.predicate = NSPredicate(
                            format: "%K IN %@",
                            #keyPath(FaviconManagedObject.urlEncrypted),
                            urls.map { $0 as NSURL }
                        )
                    }
                    fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(FaviconManagedObject.dateCreated), ascending: true)]

                    let rows = try context.fetch(fetchRequest)
                    let metadata = rows.compactMap { FaviconMetadata(dictionary: $0) }
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func fetchFaviconRows(in context: NSManagedObjectContext, matching urls: [URL]?) throws -> [FaviconStoredRow] {
        let fetchRequest = NSFetchRequest<NSDictionary>(entityName: FaviconManagedObject.entityClassName())
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = [
            #keyPath(FaviconManagedObject.identifier),
            #keyPath(FaviconManagedObject.urlEncrypted),
            #keyPath(FaviconManagedObject.documentUrlEncrypted),
            #keyPath(FaviconManagedObject.dateCreated),
            #keyPath(FaviconManagedObject.relation),
        ]
        if let urls, !urls.isEmpty {
            fetchRequest.predicate = NSPredicate(
                format: "%K IN %@",
                #keyPath(FaviconManagedObject.urlEncrypted),
                urls.map { $0 as NSURL }
            )
        }
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(FaviconManagedObject.dateCreated), ascending: true)]

        return try context.fetch(fetchRequest).compactMap { FaviconStoredRow(dictionary: $0) }
    }

    private static func makeFavicons(from rows: [FaviconStoredRow], imageStore: FaviconDiskImageStore) throws -> [Favicon] {
        guard !rows.isEmpty else { return [] }

        return rows.map { row in
            let image: NSImage?
            do {
                if let imageData = try imageStore.loadData(for: row.identifier),
                   let decodedImage = NSImage.sumiDecodedFaviconImage(data: imageData, maxPixelSize: SumiFaviconImagePolicy.maxDecodedPixelSize) {
                    image = decodedImage
                } else {
                    image = nil
                }
            } catch {
                Logger.favicons.error("Loading encoded favicon payload failed: \(error.localizedDescription)")
                try? imageStore.removeData(for: [row.identifier])
                image = nil
            }
            return row.makeFavicon(image: image)
        }
    }

    private static func compactStoreIfUseful(at storeURL: URL, reason: String) {
        do {
            if try FaviconSQLiteStoreCompactor.compactIfUseful(storeURL: storeURL) {
                Logger.favicons.debug("Compacted favicon SQLite store after \(reason, privacy: .public)")
            }
        } catch {
            Logger.favicons.debug("Skipped favicon SQLite compaction after \(reason, privacy: .public): \(error.localizedDescription)")
        }
    }

    private static func encodedImageData(for favicon: Favicon) -> Data? {
        if let imageData = favicon.imageData {
            return imageData
        }
        return favicon.image?.sumiFaviconPNGData(maxPixelSize: SumiFaviconImagePolicy.maxDecodedPixelSize)
    }

    private func remove(identifiers: [UUID], entityName: String) async throws {
        guard !identifiers.isEmpty else { return }

        return try await withCheckedThrowingContinuation { [context, imageStore, storeURL] continuation in
            context.perform {
                let deleteRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                deleteRequest.predicate = NSPredicate(format: "identifier IN %@", identifiers)

                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: deleteRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs

                do {
                    let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    let deletedObjects = result?.result as? [NSManagedObjectID] ?? []
                    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjects]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
                    if entityName == FaviconManagedObject.entityClassName() {
                        try imageStore.removeData(for: identifiers)
                        if !deletedObjects.isEmpty {
                            Self.compactStoreIfUseful(at: storeURL, reason: "favicon removal")
                        }
                    }
                    Logger.favicons.debug("\(deletedObjects.count) entries of \(entityName) removed")

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

}

fileprivate extension FaviconMetadata {

    init?(dictionary: NSDictionary) {
        guard let identifier = dictionary[#keyPath(FaviconManagedObject.identifier)] as? UUID,
              let url = dictionary.urlValue(forKey: #keyPath(FaviconManagedObject.urlEncrypted)),
              let documentUrl = dictionary.urlValue(forKey: #keyPath(FaviconManagedObject.documentUrlEncrypted)),
              let dateCreated = dictionary[#keyPath(FaviconManagedObject.dateCreated)] as? Date else {
            assertionFailure("FaviconMetadata: Failed to init metadata from dictionary result")
            return nil
        }

        self.identifier = identifier
        self.url = url
        self.documentUrl = documentUrl
        self.dateCreated = dateCreated
    }
}

private struct FaviconStoredRow {
    let identifier: UUID
    let url: URL
    let documentUrl: URL
    let dateCreated: Date
    let relation: Favicon.Relation

    init?(dictionary: NSDictionary) {
        guard let identifier = dictionary[#keyPath(FaviconManagedObject.identifier)] as? UUID,
              let url = dictionary.urlValue(forKey: #keyPath(FaviconManagedObject.urlEncrypted)),
              let documentUrl = dictionary.urlValue(forKey: #keyPath(FaviconManagedObject.documentUrlEncrypted)),
              let dateCreated = dictionary[#keyPath(FaviconManagedObject.dateCreated)] as? Date,
              let relation = dictionary.relationValue(forKey: #keyPath(FaviconManagedObject.relation)) else {
            assertionFailure("FaviconStoredRow: Failed to init row from dictionary result")
            return nil
        }

        self.identifier = identifier
        self.url = url
        self.documentUrl = documentUrl
        self.dateCreated = dateCreated
        self.relation = relation
    }

    func makeFavicon(image: NSImage?) -> Favicon {
        Favicon(
            identifier: identifier,
            url: url,
            image: image,
            relation: relation,
            documentUrl: documentUrl,
            dateCreated: dateCreated
        )
    }
}

fileprivate extension NSDictionary {
    func urlValue(forKey key: String) -> URL? {
        if let url = self[key] as? URL {
            return url
        }
        if let url = self[key] as? NSURL {
            return url as URL
        }
        return nil
    }

    func relationValue(forKey key: String) -> Favicon.Relation? {
        if let relation = self[key] as? Int64 {
            return Favicon.Relation(rawValue: Int(relation))
        }
        if let relation = self[key] as? Int {
            return Favicon.Relation(rawValue: relation)
        }
        if let relation = self[key] as? NSNumber {
            return Favicon.Relation(rawValue: relation.intValue)
        }
        return nil
    }
}

fileprivate extension FaviconHostReference {

    init?(faviconHostReferenceMO: FaviconHostReferenceManagedObject) {
        guard let identifier = faviconHostReferenceMO.identifier,
              let host = faviconHostReferenceMO.hostEncrypted as? String,
              let documentUrl = faviconHostReferenceMO.documentUrlEncrypted as? URL,
              let dateCreated = faviconHostReferenceMO.dateCreated else {
            assertionFailure("Favicon: Failed to init FaviconHostReference from FaviconHostReferenceManagedObject")
            return nil
        }

        let smallFaviconUrl = faviconHostReferenceMO.smallFaviconUrlEncrypted as? URL
        let mediumFaviconUrl = faviconHostReferenceMO.mediumFaviconUrlEncrypted as? URL

        self.init(identifier: identifier,
                  smallFaviconUrl: smallFaviconUrl,
                  mediumFaviconUrl: mediumFaviconUrl,
                  host: host,
                  documentUrl: documentUrl,
                  dateCreated: dateCreated)
    }

}

fileprivate extension FaviconUrlReference {

    init?(faviconUrlReferenceMO: FaviconUrlReferenceManagedObject) {
        guard let identifier = faviconUrlReferenceMO.identifier,
              let documentUrl = faviconUrlReferenceMO.documentUrlEncrypted as? URL,
              let dateCreated = faviconUrlReferenceMO.dateCreated else {
            assertionFailure("Favicon: Failed to init FaviconUrlReference from FaviconUrlReferenceManagedObject")
            return nil
        }

        let smallFaviconUrl = faviconUrlReferenceMO.smallFaviconUrlEncrypted as? URL
        let mediumFaviconUrl = faviconUrlReferenceMO.mediumFaviconUrlEncrypted as? URL

        self.init(identifier: identifier,
                  smallFaviconUrl: smallFaviconUrl,
                  mediumFaviconUrl: mediumFaviconUrl,
                  documentUrl: documentUrl,
                  dateCreated: dateCreated)
    }

}

fileprivate extension FaviconManagedObject {

    func update(favicon: Favicon) {
        identifier = favicon.identifier
        imageEncrypted = nil
        relation = Int64(favicon.relation.rawValue)
        urlEncrypted = favicon.url as NSURL
        documentUrlEncrypted = favicon.documentUrl as NSURL
        dateCreated = favicon.dateCreated
    }

}

private enum FaviconSQLiteStoreCompactor {

    private static let minimumFreeBytes = 1024 * 1024
    private static let minimumFreeRatio = 0.25
    private static let busyTimeoutMilliseconds: Int32 = 250

    enum CompactionError: LocalizedError {
        case openFailed(String)
        case pragmaFailed(String)
        case vacuumFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                "open failed: \(message)"
            case .pragmaFailed(let message):
                "pragma failed: \(message)"
            case .vacuumFailed(let message):
                "vacuum failed: \(message)"
            }
        }
    }

    static func compactIfUseful(storeURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { sqliteMessage($0) } ?? String(cString: sqlite3_errstr(openResult))
            if let database {
                sqlite3_close(database)
            }
            throw CompactionError.openFailed(message)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)

        let pageSize = try integerPragma("page_size", database: database)
        let pageCount = try integerPragma("page_count", database: database)
        let freePageCount = try integerPragma("freelist_count", database: database)
        guard pageSize > 0, pageCount > 0, freePageCount > 0 else {
            return false
        }

        let freeBytes = freePageCount * pageSize
        let freeRatio = Double(freePageCount) / Double(pageCount)
        guard freeBytes >= minimumFreeBytes, freeRatio >= minimumFreeRatio else {
            return false
        }

        try execute("PRAGMA wal_checkpoint(TRUNCATE);", database: database, error: CompactionError.vacuumFailed)
        try execute("VACUUM;", database: database, error: CompactionError.vacuumFailed)
        return true
    }

    private static func integerPragma(_ pragma: String, database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, "PRAGMA \(pragma);", -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CompactionError.pragmaFailed(sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CompactionError.pragmaFailed(sqliteMessage(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func execute(
        _ sql: String,
        database: OpaquePointer,
        error makeError: (String) -> CompactionError
    ) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw makeError(sqliteMessage(database))
        }
    }

    private static func sqliteMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

private final class FaviconDiskImageStore: @unchecked Sendable {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadData(for identifier: UUID) throws -> Data? {
        let url = fileURL(for: identifier)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func save(_ data: Data, for identifier: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: identifier), options: [.atomic])
    }

    func removeData(for identifiers: [UUID]) throws {
        for identifier in identifiers {
            let url = fileURL(for: identifier)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func clearAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for identifier: UUID) -> URL {
        directory.appendingPathComponent(identifier.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("favicon")
    }
}

fileprivate extension FaviconHostReferenceManagedObject {

    func update(hostReference: FaviconHostReference) {
        identifier = hostReference.identifier
        smallFaviconUrlEncrypted = hostReference.smallFaviconUrl as NSURL?
        mediumFaviconUrlEncrypted = hostReference.mediumFaviconUrl as NSURL?
        documentUrlEncrypted = hostReference.documentUrl as NSURL
        hostEncrypted = hostReference.host as NSString
        dateCreated = hostReference.dateCreated
    }

}

fileprivate extension FaviconUrlReferenceManagedObject {

    func update(urlReference: FaviconUrlReference) {
        identifier = urlReference.identifier
        smallFaviconUrlEncrypted = urlReference.smallFaviconUrl as NSURL?
        mediumFaviconUrlEncrypted = urlReference.mediumFaviconUrl as NSURL?
        documentUrlEncrypted = urlReference.documentUrl as NSURL
        dateCreated = urlReference.dateCreated
    }

}
