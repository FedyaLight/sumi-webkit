import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileWebsiteDataStoreCache {
    nonisolated static let defaultLimit = 4

    private let limit: Int
    private var storesByProfile: [UUID: WKWebsiteDataStore] = [:]
    private var storeOrder: [UUID] = []
    private var privateRuntimeProfileIDs: Set<UUID> = []

    init(limit: Int = ExtensionProfileWebsiteDataStoreCache.defaultLimit) {
        self.limit = limit
    }

    func store(
        for profileId: UUID,
        activeProfile: Profile?,
        currentProfileId: UUID?
    ) -> WKWebsiteDataStore {
        if let activeProfile {
            rememberPrivateRuntimeProfileIfNeeded(activeProfile)
            let store = activeProfile.dataStore
            storesByProfile[profileId] = store
            touch(profileId)
            return store
        }

        if let store = storesByProfile[profileId] {
            touch(profileId)
            return store
        }

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.profileStoreCreate"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.profileStoreCreate",
                signpostState
            )
        }

        let store = WKWebsiteDataStore(forIdentifier: profileId)
        storesByProfile[profileId] = store
        touch(profileId)
        evictIfNeeded(currentProfileId: currentProfileId)
        return store
    }

    func rememberPrivateRuntimeProfileIfNeeded(_ profile: Profile) {
        if profile.isEphemeral {
            privateRuntimeProfileIDs.insert(profile.id)
        }
    }

    func isPrivateRuntimeProfile(_ profileId: UUID?) -> Bool {
        guard let profileId else { return false }
        return privateRuntimeProfileIDs.contains(profileId)
    }

    func removeAll() {
        storesByProfile.removeAll()
        storeOrder.removeAll()
        privateRuntimeProfileIDs.removeAll()
    }

    func cachedStore(for profileId: UUID) -> WKWebsiteDataStore? {
        storesByProfile[profileId]
    }

    private func touch(_ profileId: UUID) {
        storeOrder.removeAll { $0 == profileId }
        storeOrder.append(profileId)
    }

    private func evictIfNeeded(currentProfileId: UUID?) {
        while storesByProfile.count > limit {
            guard let evictionID = storeOrder.first(where: {
                $0 != currentProfileId
            }) ?? storeOrder.first else {
                return
            }

            storeOrder.removeAll { $0 == evictionID }
            storesByProfile.removeValue(forKey: evictionID)
        }
    }
}
