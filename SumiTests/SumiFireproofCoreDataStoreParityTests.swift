import CoreData
import XCTest

import Persistence
@testable import Sumi

final class SumiFireproofCoreDataStoreParityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()

        for suite in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        defaultsSuites.removeAll()

        super.tearDown()
    }

    func testFireproofDatabaseContextsShareCoordinatorAndTemporaryStoreURL() throws {
        let directory = try temporaryDirectory(named: "SumiFireproofCoordinatorParity")
        let database = try makeFireproofDatabase(directory: directory)

        let firstContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiFireproofCoordinatorParityFirst"
        )
        let secondContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "SumiFireproofCoordinatorParitySecond"
        )

        let firstCoordinator = try XCTUnwrap(firstContext.persistentStoreCoordinator)
        let secondCoordinator = try XCTUnwrap(secondContext.persistentStoreCoordinator)
        let storeURL = try XCTUnwrap(firstCoordinator.persistentStores.first?.url)

        XCTAssertTrue(firstCoordinator === secondCoordinator)
        XCTAssertEqual(firstContext.name, "SumiFireproofCoordinatorParityFirst")
        XCTAssertEqual(secondContext.name, "SumiFireproofCoordinatorParitySecond")
        XCTAssertEqual(storeURL.standardizedFileURL, directory.appendingPathComponent("Permissions.sqlite").standardizedFileURL)
        XCTAssertTrue(storeURL.path.hasPrefix(directory.path))
        XCTAssertFalse(storeURL.path.hasPrefix(applicationSupportDirectory().path))
    }

    @MainActor
    func testFireproofDomainsPersistAddedAndRemovedDomainsAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "SumiFireproofReopenParity")
        let resolver = StaticRegistrableDomainResolver([
            "www.example.com": "example.com",
            "example.com": "example.com",
            "sub.example.net": "example.net",
            "example.net": "example.net",
        ])

        do {
            let domains = FireproofDomains(
                store: FireproofDomainsStore(database: try makeFireproofDatabase(directory: directory), tableName: "FireproofDomains"),
                registrableDomainResolver: resolver,
                defaults: try temporaryDefaults(named: "SumiFireproofReopenParity")
            )

            domains.add(domain: "www.example.com")
            domains.add(domain: "sub.example.net")

            XCTAssertTrue(domains.isFireproof(fireproofDomain: "example.com"))
            XCTAssertTrue(domains.isFireproof(fireproofDomain: "example.net"))
            XCTAssertTrue(domains.isFireproof(fireproofDomain: "www.example.com"))

            let removeCompleted = expectation(description: "Fireproof domain removal persisted")
            let token = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: nil
            ) { notification in
                guard (notification.object as? NSManagedObjectContext)?.name == "FireproofDomains",
                      let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>,
                      deleted.contains(where: { $0 is FireproofDomainManagedObject })
                else {
                    return
                }
                removeCompleted.fulfill()
            }
            defer {
                NotificationCenter.default.removeObserver(token)
            }

            domains.remove(domain: "www.example.com")
            wait(for: [removeCompleted], timeout: 2.0)

            XCTAssertFalse(domains.isFireproof(fireproofDomain: "example.com"))
            XCTAssertTrue(domains.isFireproof(fireproofDomain: "example.net"))
        }

        let reopenedDomains = FireproofDomains(
            store: FireproofDomainsStore(database: try makeFireproofDatabase(directory: directory), tableName: "FireproofDomains"),
            registrableDomainResolver: resolver,
            defaults: try temporaryDefaults(named: "SumiFireproofReopenParityReopened")
        )

        XCTAssertFalse(reopenedDomains.isFireproof(fireproofDomain: "example.com"))
        XCTAssertFalse(reopenedDomains.isFireproof(fireproofDomain: "www.example.com"))
        XCTAssertTrue(reopenedDomains.isFireproof(fireproofDomain: "sub.example.net"))
        XCTAssertTrue(reopenedDomains.isFireproof(fireproofDomain: "example.net"))
    }

    func testCoreDataStoreWriteContextSaveUsesTableNameAndSharedCoordinator() throws {
        let directory = try temporaryDirectory(named: "SumiCoreDataStoreWriteContextParity")
        let database = try makeFireproofDatabase(directory: directory)
        let readContext = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "FireproofDomains"
        )
        let store = FireproofDomainsStore(context: readContext)
        let saveObserved = expectation(description: "CoreDataStore write context save observed")

        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { notification in
            guard let context = notification.object as? NSManagedObjectContext,
                  context.name == "FireproofDomains"
            else {
                return
            }

            let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
            let insertedDomains = Set(inserted.compactMap {
                ($0 as? FireproofDomainManagedObject)?.valueRepresentation()
            })
            guard insertedDomains == ["write-context.example"] else { return }
            saveObserved.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(token)
        }

        _ = try store.add(["write-context.example"])

        wait(for: [saveObserved], timeout: 2.0)
        XCTAssertEqual(try store.load().domains, ["write-context.example"])
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func temporaryDefaults(named name: String) throws -> UserDefaults {
        let suite = "com.sumi.tests.\(name).\(UUID().uuidString)"
        defaultsSuites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeFireproofDatabase(directory: URL) throws -> CoreDataDatabase {
        let model = try XCTUnwrap(loadModel(named: "FireproofDomains"))
        let database = CoreDataDatabase(name: "Permissions", containerLocation: directory, model: model)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
        }
        _ = database.makeContext(concurrencyType: .privateQueueConcurrencyType, name: "PermissionsLoadWait")
        if let loadError {
            throw loadError
        }
        return database
    }

    private func loadModel(named modelName: String) -> NSManagedObjectModel? {
        let bundles = ([.main, Bundle(for: Self.self)] + Bundle.allBundles + Bundle.allFrameworks)
            .reduce(into: [String: Bundle]()) { result, bundle in
                guard bundle.resourceURL != nil else { return }
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

    private func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
}

private struct StaticRegistrableDomainResolver: SumiRegistrableDomainResolving {
    private let domainsByHost: [String: String]

    init(_ domainsByHost: [String: String]) {
        self.domainsByHost = domainsByHost
    }

    func registrableDomain(forHost host: String?) -> String? {
        guard let host else { return nil }
        return domainsByHost[host]
    }
}
