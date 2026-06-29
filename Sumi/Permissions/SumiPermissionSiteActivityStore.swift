import Combine
import Foundation
import OSLog

struct SumiPermissionSiteActivityRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let siteHost: String
    var displayDomain: String
    let permissionType: SumiPermissionType
    var hasRequested: Bool
    var hasAutoDetected: Bool
    var hasResolvedPolicy: Bool
    var hasSettingsChange: Bool
    var lastState: SumiPermissionState?
    var autoplayPolicy: SumiAutoplayPolicy?
    var source: SumiPermissionDecisionSource?
    var reason: String?
    let firstSeenAt: Date
    var updatedAt: Date
    var lastRequestedAt: Date?
    var lastAutoDetectedAt: Date?
    var lastResolvedAt: Date?
    var lastSettingsChangedAt: Date?
    var count: Int
}

@MainActor
final class SumiPermissionSiteActivityStore: ObservableObject {
    private static let log = Logger.sumi(category: "PermissionSiteActivityStore")

    enum ActivityKind {
        case requested
        case autoDetected
        case resolvedPolicy
        case settingsChanged
    }

    static let shared = SumiPermissionSiteActivityStore()

    @Published private(set) var revision = 0

    private struct StorageEnvelope: Codable {
        var version: Int
        var records: [SumiPermissionSiteActivityRecord]
    }

    private enum Constants {
        static let storageVersion = 1
        static let storageKey = "permissions.siteActivity.v1"
        static let storageFileName = "permission-site-activity.v1.json"
        static let persistentRecordLimit = 600
    }

    private let userDefaults: UserDefaults
    private let snapshotStore: SumiPermissionJSONSnapshotStore<StorageEnvelope>?
    private let domainCache: SumiPermissionDomainCache
    private var persistentRecordsById: [String: SumiPermissionSiteActivityRecord] = [:]
    private var ephemeralRecordsById: [String: SumiPermissionSiteActivityRecord] = [:]
    private var loadedUnreadablePersistentPayload = false
    private(set) var persistenceDiagnostics = SumiPermissionJSONPersistenceDiagnostics()

    init(
        userDefaults: UserDefaults = .standard,
        storageDirectory: URL? = nil,
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()
    ) {
        self.userDefaults = userDefaults
        if storageDirectory != nil || userDefaults === UserDefaults.standard {
            snapshotStore = SumiPermissionJSONSnapshotStore(
                fileName: Constants.storageFileName,
                directoryURL: storageDirectory
            )
        } else {
            snapshotStore = nil
        }
        self.domainCache = SumiPermissionDomainCache(registrableDomainResolver: registrableDomainResolver)
        persistentRecordsById = loadRecords()
        if case .loadedLegacyUserDefaults = persistenceDiagnostics.loadOutcome,
           !loadedUnreadablePersistentPayload {
            persist()
        }
    }

    func records(
        forSiteOf origin: SumiPermissionOrigin,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) -> [SumiPermissionSiteActivityRecord] {
        guard let siteHost = siteHost(for: origin) else { return [] }
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return recordsStorage(isEphemeralProfile: isEphemeralProfile).values
            .filter {
                $0.profilePartitionId == normalizedProfileId
                    && $0.isEphemeralProfile == isEphemeralProfile
                    && $0.siteHost == siteHost
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.permissionType.identity < rhs.permissionType.identity
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func record(
        event: SumiPermissionCoordinatorEvent,
        now: Date = Date()
    ) {
        switch event {
        case .queryActivated(let query), .queryPromoted(let query):
            for permissionType in query.permissionTypes.flatMap(\.expandedForPersistence) {
                let key = SumiPermissionKey(
                    requestingOrigin: query.requestingOrigin,
                    topOrigin: query.topOrigin,
                    permissionType: permissionType,
                    profilePartitionId: query.profilePartitionId,
                    isEphemeralProfile: query.isEphemeralProfile
                )
                record(
                    key: key,
                    displayDomain: query.displayDomain,
                    activity: .requested,
                    state: nil,
                    autoplayPolicy: nil,
                    source: nil,
                    reason: "permission-requested",
                    now: query.createdAt
                )
            }
        case .querySettled(_, let decision),
             .requestCancelled(_, let decision),
             .pageCancelled(_, let decision),
             .profileCancelled(_, let decision),
             .sessionCancelled(_, let decision),
             .systemBlocked(let decision),
             .promptSuppressed(_, let decision):
            record(decision: decision, now: now)
        case .queryQueued, .queryCoalesced:
            break
        }
    }

    func recordStoredRecords(
        _ records: [SumiPermissionStoreRecord],
        now: Date = Date()
    ) {
        for storedRecord in records {
            record(
                key: storedRecord.key,
                displayDomain: storedRecord.displayDomain,
                activity: .resolvedPolicy,
                state: storedRecord.decision.state,
                autoplayPolicy: storedRecord.key.permissionType == .autoplay
                    ? SumiAutoplayDecisionMapper.policy(from: storedRecord.decision)
                    : nil,
                source: storedRecord.decision.source,
                reason: storedRecord.decision.reason,
                now: storedRecord.decision.updatedAt
            )
        }
        _ = now
    }

    func recordSettingsChange(
        displayDomain: String,
        key: SumiPermissionKey,
        state: SumiPermissionState?,
        autoplayPolicy: SumiAutoplayPolicy? = nil,
        reason: String,
        now: Date = Date()
    ) {
        record(
            key: key,
            displayDomain: displayDomain,
            activity: .settingsChanged,
            state: state,
            autoplayPolicy: autoplayPolicy,
            source: .user,
            reason: reason,
            now: now
        )
    }

    func recordResolvedPolicy(
        displayDomain: String,
        key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String,
        now: Date = Date()
    ) {
        record(
            key: key,
            displayDomain: displayDomain,
            activity: .resolvedPolicy,
            state: state,
            autoplayPolicy: nil,
            source: source,
            reason: reason,
            now: now
        )
    }

    func recordAutoplayActivity(
        displayDomain: String,
        key: SumiPermissionKey,
        reason: String,
        now: Date = Date()
    ) {
        record(
            key: key,
            displayDomain: displayDomain,
            activity: .autoDetected,
            state: nil,
            autoplayPolicy: nil,
            source: .defaultSetting,
            reason: reason,
            now: now
        )
    }

    @discardableResult
    func clearSite(
        origin: SumiPermissionOrigin,
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) -> Int {
        guard let siteHost = siteHost(for: origin) else { return 0 }
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let ids = recordsStorage(isEphemeralProfile: isEphemeralProfile).values
            .filter {
                $0.profilePartitionId == normalizedProfileId
                    && $0.isEphemeralProfile == isEphemeralProfile
                    && $0.siteHost == siteHost
            }
            .map(\.id)
        guard !ids.isEmpty else { return 0 }

        if isEphemeralProfile {
            for id in ids {
                ephemeralRecordsById.removeValue(forKey: id)
            }
        } else {
            for id in ids {
                persistentRecordsById.removeValue(forKey: id)
            }
            if !loadedUnreadablePersistentPayload {
                persist()
            }
        }
        revision += 1
        return ids.count
    }

    private func record(
        decision: SumiPermissionCoordinatorDecision,
        now: Date
    ) {
        let resolvedState = decision.state ?? state(for: decision.outcome)
        for key in decision.keys {
            record(
                key: key,
                displayDomain: key.displayDomain,
                activity: .resolvedPolicy,
                state: resolvedState,
                autoplayPolicy: nil,
                source: decision.source,
                reason: decision.reason,
                now: now
            )
        }
    }

    private func record(
        key: SumiPermissionKey,
        displayDomain: String,
        activity: ActivityKind,
        state: SumiPermissionState?,
        autoplayPolicy: SumiAutoplayPolicy?,
        source: SumiPermissionDecisionSource?,
        reason: String?,
        now: Date
    ) {
        guard let siteHost = siteHost(for: key.topOrigin.isWebOrigin ? key.topOrigin : key.requestingOrigin) else {
            return
        }

        let id = Self.recordId(
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: key.isEphemeralProfile,
            siteHost: siteHost,
            permissionType: key.permissionType
        )
        var storage = recordsStorage(isEphemeralProfile: key.isEphemeralProfile)
        let existing = storage[id]
        var record = existing ?? SumiPermissionSiteActivityRecord(
            id: id,
            profilePartitionId: key.profilePartitionId,
            isEphemeralProfile: key.isEphemeralProfile,
            siteHost: siteHost,
            displayDomain: displayDomain,
            permissionType: key.permissionType,
            hasRequested: false,
            hasAutoDetected: false,
            hasResolvedPolicy: false,
            hasSettingsChange: false,
            lastState: nil,
            autoplayPolicy: nil,
            source: nil,
            reason: nil,
            firstSeenAt: now,
            updatedAt: now,
            lastRequestedAt: nil,
            lastAutoDetectedAt: nil,
            lastResolvedAt: nil,
            lastSettingsChangedAt: nil,
            count: 0
        )

        record.displayDomain = displayDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record.displayDomain
            : displayDomain
        record.updatedAt = max(record.updatedAt, now)
        record.count += 1
        record.source = source ?? record.source
        record.reason = reason ?? record.reason
        if let state {
            record.lastState = state
        }
        if let autoplayPolicy {
            record.autoplayPolicy = autoplayPolicy
        }

        switch activity {
        case .requested:
            record.hasRequested = true
            record.lastRequestedAt = now
        case .autoDetected:
            record.hasAutoDetected = true
            record.lastAutoDetectedAt = now
        case .resolvedPolicy:
            if state == .allow || state == .deny || autoplayPolicy != nil {
                record.hasResolvedPolicy = true
                record.lastResolvedAt = now
            }
        case .settingsChanged:
            record.hasSettingsChange = true
            record.lastSettingsChangedAt = now
            if state == .allow || state == .deny || autoplayPolicy != nil {
                record.hasResolvedPolicy = true
                record.lastResolvedAt = now
            }
        }

        guard storage[id] != record else { return }
        storage[id] = record
        write(storage, isEphemeralProfile: key.isEphemeralProfile)
        revision += 1
    }

    private func recordsStorage(
        isEphemeralProfile: Bool
    ) -> [String: SumiPermissionSiteActivityRecord] {
        isEphemeralProfile ? ephemeralRecordsById : persistentRecordsById
    }

    private func write(
        _ storage: [String: SumiPermissionSiteActivityRecord],
        isEphemeralProfile: Bool
    ) {
        if isEphemeralProfile {
            ephemeralRecordsById = storage
        } else {
            persistentRecordsById = capped(storage)
            loadedUnreadablePersistentPayload = false
            persist()
        }
    }

    private func capped(
        _ records: [String: SumiPermissionSiteActivityRecord]
    ) -> [String: SumiPermissionSiteActivityRecord] {
        guard records.count > Constants.persistentRecordLimit else { return records }
        return Dictionary(
            uniqueKeysWithValues: records.values
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(Constants.persistentRecordLimit)
                .map { ($0.id, $0) }
        )
    }

    private func persist() {
        let envelope = StorageEnvelope(
            version: Constants.storageVersion,
            records: Array(persistentRecordsById.values)
        )

        if let snapshotStore {
            do {
                try snapshotStore.write(envelope)
                persistenceDiagnostics.lastWriteFailure = nil
                return
            } catch {
                persistenceDiagnostics.lastWriteFailure = error.localizedDescription
                Self.log.error(
                    "Failed to persist permission site activity to file: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        do {
            let data = try JSONEncoder().encode(envelope)
            userDefaults.set(data, forKey: Constants.storageKey)
        } catch {
            persistenceDiagnostics.lastWriteFailure = error.localizedDescription
            Self.log.error(
                "Failed to encode permission site activity: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadRecords() -> [String: SumiPermissionSiteActivityRecord] {
        if let snapshotStore {
            switch snapshotStore.load() {
            case .missing:
                break
            case .loaded(let envelope, let data):
                guard envelope.version == Constants.storageVersion else {
                    snapshotStore.preserveUnreadablePayload(data)
                    loadedUnreadablePersistentPayload = true
                    persistenceDiagnostics.loadOutcome = .unsupportedFileVersion(envelope.version)
                    return [:]
                }
                persistenceDiagnostics.loadOutcome = .loadedFile
                return Dictionary(uniqueKeysWithValues: envelope.records.map { ($0.id, $0) })
            case .failed(let failure):
                loadedUnreadablePersistentPayload = true
                switch failure.kind {
                case .read:
                    persistenceDiagnostics.loadOutcome = .failedFileRead(failure.description)
                case .decode:
                    persistenceDiagnostics.loadOutcome = .failedFileDecode(failure.description)
                case .write:
                    persistenceDiagnostics.lastWriteFailure = failure.description
                }
                return [:]
            }
        }

        guard let data = userDefaults.data(forKey: Constants.storageKey) else {
            persistenceDiagnostics.loadOutcome = .missing
            return [:]
        }
        let envelope: StorageEnvelope
        do {
            envelope = try JSONDecoder().decode(StorageEnvelope.self, from: data)
        } catch {
            Self.preserveUnreadablePayload(data, in: userDefaults, storageKey: Constants.storageKey)
            loadedUnreadablePersistentPayload = true
            persistenceDiagnostics.loadOutcome = .failedLegacyUserDefaultsDecode(error.localizedDescription)
            return [:]
        }
        guard envelope.version == Constants.storageVersion else {
            Self.preserveUnreadablePayload(data, in: userDefaults, storageKey: Constants.storageKey)
            loadedUnreadablePersistentPayload = true
            persistenceDiagnostics.loadOutcome = .unsupportedFileVersion(envelope.version)
            return [:]
        }
        persistenceDiagnostics.loadOutcome = .loadedLegacyUserDefaults
        return Dictionary(uniqueKeysWithValues: envelope.records.map { ($0.id, $0) })
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

    private func siteHost(for origin: SumiPermissionOrigin) -> String? {
        guard origin.isWebOrigin, let host = origin.host else { return nil }
        return (domainCache.registrableDomain(forHost: host) ?? host).lowercased()
    }

    private static func recordId(
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        siteHost: String,
        permissionType: SumiPermissionType
    ) -> String {
        [
            SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId),
            isEphemeralProfile ? "ephemeral" : "persistent",
            siteHost.lowercased(),
            permissionType.identity,
        ].joined(separator: "|")
    }

    private func state(
        for outcome: SumiPermissionCoordinatorOutcome
    ) -> SumiPermissionState? {
        switch outcome {
        case .granted:
            return .allow
        case .denied, .systemBlocked, .suppressed:
            return .deny
        case .promptRequired:
            return .ask
        case .unsupported, .requiresUserActivation, .cancelled, .dismissed, .ignored, .expired:
            return nil
        }
    }
}
