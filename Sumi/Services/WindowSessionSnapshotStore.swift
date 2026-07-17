import Foundation
import OSLog

enum WindowSessionSnapshotSource: Equatable, Sendable {
    case userDefaultsKey(String)
    case overrideFile(URL)

    var description: String {
        switch self {
        case .userDefaultsKey(let key):
            return "UserDefaults(\(key))"
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
    private let userDefaults: UserDefaults
    private let environment: () -> [String: String]
    private let codec: WindowSessionSnapshotCodec
    private var cachedPersistedData: Data?

    private(set) var lastLoadFailure: WindowSessionSnapshotLoadFailure?
    private(set) var lastPersistFailure: String?

    init(
        key: String,
        userDefaults: UserDefaults = .standard,
        environment: @escaping () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        codec: WindowSessionSnapshotCodec = WindowSessionSnapshotCodec()
    ) {
        self.key = key
        self.userDefaults = userDefaults
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
        } else if let data = userDefaults.data(forKey: key) {
            result = codec.decode(data, source: .userDefaultsKey(key))
        } else {
            result = .missing
        }

        switch result {
        case .missing:
            lastLoadFailure = nil
        case .loaded(_, let data):
            lastLoadFailure = nil
            cachedPersistedData = data
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

        let previous = cachedPersistedData ?? userDefaults.data(forKey: key)
        guard previous != data else { return false }
        userDefaults.set(data, forKey: key)
        cachedPersistedData = data
        return true
    }

    /// Migrates the browser-owned UserDefaults snapshot. An override file is
    /// external test input and remains immutable; restore admission validates it.
    func migrateDurableWindowProfileReference(
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> Bool {
        switch loadUserDefaultsResult() {
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
        switch loadUserDefaultsResult() {
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
    }

    private func loadUserDefaultsResult() -> WindowSessionSnapshotLoadResult {
        guard let data = userDefaults.data(forKey: key) else {
            return .missing
        }
        return codec.decode(data, source: .userDefaultsKey(key))
    }

    private func persistAndVerify(_ snapshot: WindowSessionSnapshot) -> Bool {
        let data: Data
        do {
            data = try codec.encode(snapshot)
        } catch {
            lastPersistFailure = error.localizedDescription
            return false
        }
        userDefaults.set(data, forKey: key)
        guard userDefaults.data(forKey: key) == data else {
            lastPersistFailure = "UserDefaults rejected the window session write"
            return false
        }
        cachedPersistedData = data
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
