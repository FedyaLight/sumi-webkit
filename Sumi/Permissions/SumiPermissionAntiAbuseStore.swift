import Foundation

protocol SumiPermissionAntiAbuseStoring: Sendable {
    func record(_ event: SumiPermissionAntiAbuseEvent) async
    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent]
    func allEvents(profilePartitionId: String, isEphemeralProfile: Bool, now: Date) async -> [SumiPermissionAntiAbuseEvent]
    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async
}

actor SumiPermissionAntiAbuseStore: SumiPermissionAntiAbuseStoring {
    private enum Constants {
        static let storageKey = "permissions.anti-abuse.events.v1"
    }

    private let userDefaults: UserDefaults?
    private let storageKey: String
    private let retentionInterval: TimeInterval
    private let maximumEventsPerProfile: Int
    private var loaded = false
    private var records: [SumiPermissionAntiAbuseEvent] = []

    init(
        userDefaults: UserDefaults? = .standard,
        storageKey: String = Constants.storageKey,
        retentionInterval: TimeInterval = SumiPermissionPromptCooldown.eventRetention,
        maximumEventsPerProfile: Int = SumiPermissionPromptCooldown.maximumEventsPerProfile
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.retentionInterval = retentionInterval
        self.maximumEventsPerProfile = max(1, maximumEventsPerProfile)
    }

    static func memoryOnly(
        retentionInterval: TimeInterval = SumiPermissionPromptCooldown.eventRetention,
        maximumEventsPerProfile: Int = SumiPermissionPromptCooldown.maximumEventsPerProfile
    ) -> SumiPermissionAntiAbuseStore {
        SumiPermissionAntiAbuseStore(
            userDefaults: nil,
            retentionInterval: retentionInterval,
            maximumEventsPerProfile: maximumEventsPerProfile
        )
    }

    func record(_ event: SumiPermissionAntiAbuseEvent) async {
        loadIfNeeded()
        records.append(event)
        prune(now: event.createdAt)
        persistIfNeeded()
    }

    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent] {
        loadIfNeeded()
        prune(now: now)
        persistIfNeeded()
        return records
            .filter {
                $0.key.persistentIdentity == key.persistentIdentity
                    && $0.key.isEphemeralProfile == key.isEphemeralProfile
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func allEvents(
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        now: Date
    ) async -> [SumiPermissionAntiAbuseEvent] {
        loadIfNeeded()
        prune(now: now)
        persistIfNeeded()
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records
            .filter {
                $0.key.profilePartitionId == profileId
                    && $0.key.isEphemeralProfile == isEphemeralProfile
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func clearSuppressionState(for key: SumiPermissionKey, now: Date) async {
        loadIfNeeded()
        records.removeAll {
            $0.key.persistentIdentity == key.persistentIdentity
                && $0.key.isEphemeralProfile == key.isEphemeralProfile
                && Self.isSuppressionStateEvent($0.type)
        }
        prune(now: now)
        persistIfNeeded()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let userDefaults,
              let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SumiPermissionAntiAbuseEvent].self, from: data)
        else {
            records = []
            return
        }
        records = decoded
    }

    private func persistIfNeeded() {
        guard let userDefaults else { return }
        let persistentRecords = records.filter { !$0.key.isEphemeralProfile }
        if let data = try? JSONEncoder().encode(persistentRecords) {
            userDefaults.set(data, forKey: storageKey)
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
