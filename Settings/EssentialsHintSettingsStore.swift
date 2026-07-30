//
//  EssentialsHintSettingsStore.swift
//  Sumi
//

import Foundation

/// Remembers which profiles have dismissed the empty-Essentials placeholder.
///
/// Essentials are stored per profile, so the hint is dismissed per profile too:
/// closing it in one profile must not hide the affordance for a profile that has
/// never had an Essential. The dismissed ids are kept as an in-memory `Set` so
/// the sidebar's per-frame read is an O(1) hash lookup; the durable form is a
/// sorted `[String]` of UUIDs, written only when a profile is first dismissed.
@MainActor
@Observable
final class EssentialsHintSettingsStore {
    private let userDefaults: UserDefaults
    private let dismissedProfileIdsKey: String

    private(set) var dismissedProfileIds: Set<UUID>

    init(
        userDefaults: UserDefaults,
        dismissedProfileIdsKey: String
    ) {
        self.userDefaults = userDefaults
        self.dismissedProfileIdsKey = dismissedProfileIdsKey
        self.dismissedProfileIds = Set(
            (userDefaults.stringArray(forKey: dismissedProfileIdsKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    /// `false` for a nil profile: with no resolved profile there is nothing to
    /// drop an Essential into, so the placeholder would be a dead target.
    func showsPlaceholder(profileId: UUID?) -> Bool {
        guard let profileId else { return false }
        return !dismissedProfileIds.contains(profileId)
    }

    func dismissPlaceholder(profileId: UUID) {
        guard dismissedProfileIds.insert(profileId).inserted else { return }
        Persisted.stringArray(
            dismissedProfileIds.map(\.uuidString).sorted(),
            key: dismissedProfileIdsKey,
            defaults: userDefaults
        )
    }
}
