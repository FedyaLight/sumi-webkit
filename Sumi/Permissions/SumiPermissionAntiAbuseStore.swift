import Foundation
import OSLog

protocol SumiPermissionAntiAbuseStoring: Sendable {
    func record(_ event: SumiPermissionAntiAbuseEvent) async
    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent]
    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async
}

actor SumiPermissionAntiAbuseStore: SumiPermissionAntiAbuseStoring {
    private static let log = Logger.sumi(category: "PermissionAntiAbuseStore")

    private struct StorageEnvelope: Codable, Sendable {
        var version: Int
        var records: [SumiPermissionAntiAbuseEvent]
    }

    private enum Constants {
        static let storageVersion = 1
        static let storageKey = "permissions.anti-abuse.events.v1"
        static let storageFileName = "permission-anti-abuse-events.v1.json"
    }

    private let userDefaults: UserDefaults?
    private let storageKey: String
    private let snapshotStore: SumiPermissionJSONSnapshotStore<StorageEnvelope>?
    private let retentionInterval: TimeInterval
    private let maximumEventsPerProfile: Int
    private var loaded = false
    private var loadedUnreadablePersistentPayload = false
    private var records: [SumiPermissionAntiAbuseEvent] = []
    private(set) var persistenceDiagnostics = SumiPermissionJSONPersistenceDiagnostics()

    init(
        userDefaults: UserDefaults? = .standard,
        storageKey: String = Constants.storageKey,
        storageDirectory: URL? = nil,
        retentionInterval: TimeInterval = SumiPermissionPromptCooldown.eventRetention,
        maximumEventsPerProfile: Int = SumiPermissionPromptCooldown.maximumEventsPerProfile
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        if let userDefaults,
           storageDirectory != nil || userDefaults === UserDefaults.standard {
            snapshotStore = SumiPermissionJSONSnapshotStore(
                fileName: Constants.storageFileName,
                directoryURL: storageDirectory
            )
        } else {
            snapshotStore = nil
        }
        self.retentionInterval = retentionInterval
        self.maximumEventsPerProfile = max(1, maximumEventsPerProfile)
    }

    func record(_ event: SumiPermissionAntiAbuseEvent) async {
        loadIfNeeded()
        records.append(event)
        prune(now: event.createdAt)
        loadedUnreadablePersistentPayload = false
        persistIfNeeded()
    }

    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent] {
        loadIfNeeded()
        prune(now: now)
        if !loadedUnreadablePersistentPayload {
            persistIfNeeded()
        }
        return records
            .filter {
                $0.key.persistentIdentity == key.persistentIdentity
                    && $0.key.isEphemeralProfile == key.isEphemeralProfile
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async {
        loadIfNeeded()
        guard !loadedUnreadablePersistentPayload else { return }
        records.removeAll {
            $0.key.persistentIdentity == key.persistentIdentity
                && $0.key.isEphemeralProfile == key.isEphemeralProfile
                && Self.isSuppressionStateEvent($0.type)
        }
        prune(now: now)
        persistIfNeeded()
    }

    func diagnostics() -> SumiPermissionJSONPersistenceDiagnostics {
        loadIfNeeded()
        return persistenceDiagnostics
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        if let snapshotStore {
            switch snapshotStore.load() {
            case .missing:
                break
            case .loaded(let envelope, let data):
                guard envelope.version == Constants.storageVersion else {
                    snapshotStore.preserveUnreadablePayload(data)
                    records = []
                    loadedUnreadablePersistentPayload = true
                    persistenceDiagnostics.loadOutcome = .unsupportedFileVersion(envelope.version)
                    return
                }
                records = envelope.records
                persistenceDiagnostics.loadOutcome = .loadedFile
                return
            case .failed(let failure):
                records = []
                loadedUnreadablePersistentPayload = true
                switch failure.kind {
                case .read:
                    persistenceDiagnostics.loadOutcome = .failedFileRead(failure.description)
                case .decode:
                    persistenceDiagnostics.loadOutcome = .failedFileDecode(failure.description)
                case .write:
                    persistenceDiagnostics.lastWriteFailure = failure.description
                }
                return
            }
        }

        guard let userDefaults else {
            records = []
            persistenceDiagnostics.loadOutcome = .missing
            return
        }

        guard let data = userDefaults.data(forKey: storageKey) else {
            records = []
            persistenceDiagnostics.loadOutcome = .missing
            return
        }

        do {
            records = try JSONDecoder().decode([SumiPermissionAntiAbuseEvent].self, from: data)
            persistenceDiagnostics.loadOutcome = .loadedLegacyUserDefaults
            if snapshotStore != nil {
                persistIfNeeded()
            }
        } catch {
            Self.preserveUnreadablePayload(data, in: userDefaults, storageKey: storageKey)
            records = []
            loadedUnreadablePersistentPayload = true
            persistenceDiagnostics.loadOutcome = .failedLegacyUserDefaultsDecode(error.localizedDescription)
        }
    }

    private func persistIfNeeded() {
        guard let userDefaults else { return }
        let persistentRecords = records.filter { !$0.key.isEphemeralProfile }

        if let snapshotStore {
            do {
                try snapshotStore.write(
                    StorageEnvelope(
                        version: Constants.storageVersion,
                        records: persistentRecords
                    )
                )
                persistenceDiagnostics.lastWriteFailure = nil
                return
            } catch {
                persistenceDiagnostics.lastWriteFailure = error.localizedDescription
                Self.log.error(
                    "Failed to persist anti-abuse permission events to file: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        do {
            let data = try JSONEncoder().encode(persistentRecords)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            persistenceDiagnostics.lastWriteFailure = error.localizedDescription
            Self.log.error(
                "Failed to encode anti-abuse permission events: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        records = records.filter { $0.createdAt >= cutoff }

        let grouped = Dictionary(grouping: records) { event in
            [
                event.key.profilePartitionId,
                event.key.isEphemeralProfile ? "ephemeral" : "persistent",
            ].joined(separator: "|")
        }
        records = grouped.values.flatMap { events in
            events
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(maximumEventsPerProfile)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    private static func preserveUnreadablePayload(
        _ data: Data,
        in userDefaults: UserDefaults,
        storageKey: String
    ) {
        let backupKey = "\(storageKey).unreadable"
        guard userDefaults.data(forKey: backupKey) == nil else { return }
        userDefaults.set(data, forKey: backupKey)
    }

    private static func isSuppressionStateEvent(_ type: SumiPermissionAntiAbuseEvent.EventType) -> Bool {
        switch type {
        case .userDismissed,
             .userDenied,
             .requestSuppressedByCooldown,
             .requestSuppressedByEmbargo,
             .systemBlocked,
             .blockedByDefaultPolicy:
            return true
        case .promptShown,
             .userAllowed,
             .requestCancelledByNavigation,
             .autoRevokedByCleanup:
            return false
        }
    }
}
