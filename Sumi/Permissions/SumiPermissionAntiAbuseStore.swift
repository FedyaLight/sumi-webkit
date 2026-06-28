import Foundation

protocol SumiPermissionAntiAbuseStoring: Sendable {
    func record(_ event: SumiPermissionAntiAbuseEvent) async
    func events(for key: SumiPermissionKey, now: Date) async -> [SumiPermissionAntiAbuseEvent]
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
              let data = userDefaults.data(forKey: storageKey)
        else {
            records = []
            return
        }
        do {
            records = try JSONDecoder().decode([SumiPermissionAntiAbuseEvent].self, from: data)
        } catch {
            Self.preserveUnreadablePayload(data, in: userDefaults, storageKey: storageKey)
            records = []
        }
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
