import Foundation

@testable import Sumi

private final class TestFaviconDatabaseRegistry: @unchecked Sendable {
    static let shared = TestFaviconDatabaseRegistry()

    private let lock = NSLock()
    private var databases: [String: SumiDatabase] = [:]

    func database(for rootDirectory: URL) -> SumiDatabase {
        lock.withLock {
            let key = rootDirectory.standardizedFileURL.path
            if let database = databases[key] {
                return database
            }
            let database = try! SumiDatabase.inMemory()
            databases[key] = database
            return database
        }
    }
}

@MainActor
func installTestProfile(
    _ profile: Profile,
    in database: SumiDatabase
) throws {
    try database.transaction { connection in
        guard try connection.profiles.all().contains(where: {
            $0.id == profile.id
        }) == false else {
            return
        }
        let nextIndex = try connection.profiles.all().count
        try connection.profiles.save(
            ProfileRecord(
                id: profile.id,
                name: profile.name,
                index: nextIndex
            )
        )
    }
}

extension SumiFaviconRuntime {
    convenience init(
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            database: TestFaviconDatabaseRegistry.shared.database(
                for: rootDirectory
            ),
            rootDirectory: rootDirectory,
            fetcher: fetcher,
            notificationCenter: notificationCenter
        )
    }
}

extension SumiFaviconSystem {
    convenience init(
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching
    ) {
        self.init(
            database: TestFaviconDatabaseRegistry.shared.database(
                for: rootDirectory
            ),
            rootDirectory: rootDirectory,
            fetcher: fetcher
        )
    }
}

extension SumiFaviconBlobStorage {
    init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        persistCoalesceInterval: TimeInterval = 0.75
    ) {
        self.init(
            database: TestFaviconDatabaseRegistry.shared.database(
                for: rootDirectory
            ),
            rootDirectory: rootDirectory,
            fileManager: fileManager,
            persistCoalesceInterval: persistCoalesceInterval
        )
    }
}

extension SumiPermissionPersistenceAuthority {
    convenience init() {
        self.init(database: try! SumiDatabase.inMemory())
    }
}

@MainActor
extension SumiPermissionSiteActivityStore {
    convenience init() {
        self.init(persistenceAuthority: SumiPermissionPersistenceAuthority())
    }
}

@MainActor
extension LastSessionWindowsStore {
    convenience init() {
        self.init(database: try! SumiDatabase.inMemory())
    }
}

@MainActor
extension WindowSessionSnapshotStore {
    private static let testDatabase = try! SumiDatabase.inMemory()

    convenience init(
        key: String,
        environment: @escaping () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        codec: WindowSessionSnapshotCodec = WindowSessionSnapshotCodec()
    ) {
        self.init(
            database: Self.testDatabase,
            key: key,
            environment: environment,
            codec: codec
        )
    }
}
