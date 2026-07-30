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

    /// Registers the browser-owned store before any controller is created.
    /// A profile is represented by one WKWebsiteDataStore object for the
    /// lifetime of the runtime; recreating a store with the same identifier
    /// still breaks WebKit's object-identity checks on configurations.
    /// A cached store that disagrees with the profile's own store is replaced,
    /// so a browser-owned store always wins over one this cache minted.
    func remember(_ profile: Profile) {
        let profileID = profile.id
        if storesByProfile[profileID] !== profile.dataStore {
            storesByProfile[profileID] = profile.dataStore
            touch(profileID)
        }
        rememberPrivateRuntimeProfileIfNeeded(profile)
    }

    /// Resolves the one store object that represents this profile, minting a
    /// persistent store only for a profile that can own one.
    /// A private partition's store is non-persistent and therefore not
    /// reconstructible from a UUID, so resolution fails closed rather than
    /// minting persistent storage for a private browsing session.
    func store(
        for profileId: UUID,
        activeProfile: Profile?,
        currentProfileId: UUID?
    ) -> WKWebsiteDataStore? {
        if let activeProfile, activeProfile.id == profileId {
            remember(activeProfile)
            return activeProfile.dataStore
        }

        if let store = storesByProfile[profileId] {
            touch(profileId)
            return store
        }

        guard isPrivateRuntimeProfile(profileId) == false else {
            RuntimeDiagnostics.emit(
                "🔒 [ExtensionProfileStoreCache] Refused persistent store for private partition: \(profileId.uuidString)"
            )
            return nil
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

    func remove(profileID: UUID) {
        storesByProfile.removeValue(forKey: profileID)
        storeOrder.removeAll { $0 == profileID }
        privateRuntimeProfileIDs.remove(profileID)
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        storesByProfile[profileID] != nil
            || storeOrder.contains(profileID)
            || privateRuntimeProfileIDs.contains(profileID)
    }

    func cachedStore(for profileId: UUID) -> WKWebsiteDataStore? {
        storesByProfile[profileId]
    }

    private func touch(_ profileId: UUID) {
        storeOrder.removeAll { $0 == profileId }
        storeOrder.append(profileId)
    }

    /// Evicts least recently used persistent stores, which resolution can mint
    /// again on demand. The current profile and every private partition are
    /// never evicted: a private partition's non-persistent store cannot be
    /// recreated from its UUID, so dropping it would either fail resolution or
    /// leak the session onto disk. The cache therefore exceeds `limit` while
    /// enough private windows are open, which is the intended trade.
    private func evictIfNeeded(currentProfileId: UUID?) {
        while storesByProfile.count > limit {
            guard let evictionID = storeOrder.first(where: {
                $0 != currentProfileId && isPrivateRuntimeProfile($0) == false
            }) else {
                return
            }

            storeOrder.removeAll { $0 == evictionID }
            storesByProfile.removeValue(forKey: evictionID)
        }
    }
}
