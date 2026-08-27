import Foundation
import OSLog

enum WindowSessionSnapshotSource: Equatable, Sendable {
    case databaseKey(String)
    case overrideFile(URL)

    var description: String {
        switch self {
        case .databaseKey(let key):
            return "Sumi.sqlite(\(key))"
        case .overrideFile(let url):
            return url.path
        }
    }
}

struct WindowSessionSnapshotLoadFailure: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case readFailed
        case decodeFailed
    }

    var source: WindowSessionSnapshotSource
    var reason: Reason
    var message: String
}

enum WindowSessionSnapshotLoadResult {
    case missing
    case loaded(snapshot: WindowSessionSnapshot, data: Data)
    case failed(WindowSessionSnapshotLoadFailure)
}

struct WindowSessionSnapshotCodec {
    func encode(_ snapshot: WindowSessionSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    func decode(
        _ data: Data,
        source: WindowSessionSnapshotSource
    ) -> WindowSessionSnapshotLoadResult {
        do {
            return .loaded(
                snapshot: try JSONDecoder().decode(
                    WindowSessionSnapshot.self,
                    from: data
                ),
                data: data
            )
        } catch {
            return .failed(
                WindowSessionSnapshotLoadFailure(
                    source: source,
                    reason: .decodeFailed,
                    message: error.localizedDescription
                )
            )
        }
    }
}

/// Durable boundary for the single global window-session snapshot.
/// Encoding, override-file precedence, deduplication, and I/O diagnostics live
/// here; restore-cycle and UI reconciliation state do not.
@MainActor
final class WindowSessionSnapshotStore {
    static let overridePathEnvironmentKey =
        "SUMI_WINDOW_SESSION_OVERRIDE_PATH"

    private static let log = Logger.sumi(category: "WindowSessionSnapshotStore")

    private let key: String
    private let database: SumiDatabase
    private let environment: () -> [String: String]
    private let codec: WindowSessionSnapshotCodec
    private var cachedPersistedData: Data?
    private var cachedSnapshot: WindowSessionSnapshot?
    private var pendingPersistCount = 0

    private(set) var lastLoadFailure: WindowSessionSnapshotLoadFailure?
    private(set) var lastPersistFailure: String?

    init(
        database: SumiDatabase,
        key: String,
        environment: @escaping () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        codec: WindowSessionSnapshotCodec = WindowSessionSnapshotCodec()
    ) {
        self.key = key
        self.database = database
        self.environment = environment
        self.codec = codec
    }

    func loadSnapshot() -> (snapshot: WindowSessionSnapshot, data: Data)? {
        guard case .loaded(let snapshot, let data) = loadResult() else {
            return nil
        }
        return (snapshot, data)
    }

    func loadResult() -> WindowSessionSnapshotLoadResult {
        let result: WindowSessionSnapshotLoadResult
        if let overrideResult = loadOverrideResult() {
            result = overrideResult
        } else if let cachedSnapshot {
            do {
                result = .loaded(
                    snapshot: cachedSnapshot,
                    data: try codec.encode(cachedSnapshot)
                )
            } catch {
                result = .failed(
                    WindowSessionSnapshotLoadFailure(
                        source: .databaseKey(key),
                        reason: .decodeFailed,
                        message: error.localizedDescription
                    )
                )
            }
        } else {
            result = loadDatabaseResult()
        }

        switch result {
        case .missing:
            lastLoadFailure = nil
        case .loaded(_, let data):
            lastLoadFailure = nil
            cachedPersistedData = data
            if case .loaded(let snapshot, _) = result {
                cachedSnapshot = snapshot
            }
        case .failed(let failure):
            lastLoadFailure = failure
            Self.log.error(
                "Failed to load window session from \(failure.source.description, privacy: .public): \(failure.message, privacy: .public)"
            )
        }
        return result
    }

    @discardableResult
    func persist(_ snapshot: WindowSessionSnapshot) -> Bool {
        database.flushEnqueuedTransactions()
        let data: Data
        do {
            data = try codec.encode(snapshot)
            lastPersistFailure = nil
        } catch {
            lastPersistFailure = error.localizedDescription
            Self.log.error(
                "Failed to encode window session snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        let previous = cachedPersistedData ?? (try? database.read {
            try $0.documents.data(forKey: key)
        })
        guard previous != data else { return false }
        do {
            try database.transaction {
                try $0.documents.save(data, forKey: key)
            }
        } catch {
            lastPersistFailure = error.localizedDescription
            Self.log.error(
                "Failed to persist window session snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        cachedPersistedData = data
        cachedSnapshot = snapshot
        return true
    }

    @discardableResult
    func enqueuePersist(_ snapshot: WindowSessionSnapshot) -> Bool {
        guard cachedSnapshot != snapshot else { return false }
        cachedSnapshot = snapshot
        cachedPersistedData = nil

        struct Payload: @unchecked Sendable {
            let snapshot: WindowSessionSnapshot
        }
        let payload = Payload(snapshot: snapshot)
        let codec = codec
        let key = key
        pendingPersistCount += 1
        database.enqueueTransaction(
            { connection in
                let data = try codec.encode(payload.snapshot)
                try connection.documents.save(data, forKey: key)
            },
            completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingPersistCount -= 1
                    switch result {
                    case .success:
                        if self.cachedSnapshot == payload.snapshot {
                            self.lastPersistFailure = nil
                        }
                    case .failure(let error):
                        self.lastPersistFailure = error.localizedDescription
                        Self.log.error(
                            "Failed to persist window session snapshot: \(error.localizedDescription, privacy: .public)"
                        )
                        if self.cachedSnapshot == payload.snapshot {
                            self.cachedSnapshot = nil
                            self.cachedPersistedData = nil
                        }
                    }
                }
            }
        )
        return true
    }

    func flushPendingPersistence() {
        database.flushEnqueuedTransactions()
    }

    /// Migrates the browser-owned database snapshot. An override file is
    /// external test input and remains immutable; restore admission validates it.
    func migrateDurableWindowProfileReference(
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> Bool {
        database.flushEnqueuedTransactions()
        switch loadDatabaseResult() {
        case .missing:
            return true
        case .failed:
            return false
        case .loaded(var snapshot, _):
            guard snapshot.currentProfileId == deletedProfileID else {
                return true
            }
            snapshot.currentProfileId = fallbackProfileID
            return persistAndVerify(snapshot)
        }
    }

    func containsDurableWindowProfileReference(to profileID: UUID) -> Bool {
        database.flushEnqueuedTransactions()
        switch loadDatabaseResult() {
        case .missing:
            return false
        case .failed:
            return true
        case .loaded(let snapshot, _):
            return ProfileReferenceInventory(windowSnapshot: snapshot)
                .contains(profileID)
        }
    }

    func resetCycleCache() {
        cachedPersistedData = nil
        if pendingPersistCount == 0 {
            cachedSnapshot = nil
        }
    }

    private func loadDatabaseResult() -> WindowSessionSnapshotLoadResult {
        let data: Data?
        do {
            data = try database.read {
                try $0.documents.data(forKey: key)
            }
        } catch {
            return .failed(
                WindowSessionSnapshotLoadFailure(
                    source: .databaseKey(key),
                    reason: .readFailed,
                    message: error.localizedDescription
                )
            )
        }
        guard let data else {
            return .missing
        }
        return codec.decode(data, source: .databaseKey(key))
    }

    private func persistAndVerify(_ snapshot: WindowSessionSnapshot) -> Bool {
        let data: Data
        do {
            data = try codec.encode(snapshot)
        } catch {
            lastPersistFailure = error.localizedDescription
            return false
        }
        do {
            try database.transaction {
                try $0.documents.save(data, forKey: key)
            }
        } catch {
            lastPersistFailure = error.localizedDescription
            return false
        }
        cachedPersistedData = data
        cachedSnapshot = snapshot
        lastPersistFailure = nil
        return true
    }

    private func loadOverrideResult() -> WindowSessionSnapshotLoadResult? {
        guard let path = environment()[Self.overridePathEnvironmentKey],
              path.isEmpty == false else {
            return nil
        }

        let url = URL(fileURLWithPath: path, isDirectory: false)
        do {
            return codec.decode(
                try Data(contentsOf: url),
                source: .overrideFile(url)
            )
        } catch {
            return .failed(
                WindowSessionSnapshotLoadFailure(
                    source: .overrideFile(url),
                    reason: .readFailed,
                    message: error.localizedDescription
                )
            )
        }
    }
}
