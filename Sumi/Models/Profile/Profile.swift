//
//  Profile.swift
//  Sumi
//
//  Runtime profile model representing a browsing persona.
//  Each Profile now owns a persistent, isolated WKWebsiteDataStore
//  to provide strong data separation across profiles.
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class Profile: NSObject, Identifiable {
    let id: UUID
    var name: String
    @ObservationIgnored private let explicitDataStore: WKWebsiteDataStore?
    @ObservationIgnored private var cachedPersistentDataStore: WKWebsiteDataStore?
    @ObservationIgnored private var persistentDataStoreWasRemoved = false
    var dataStore: WKWebsiteDataStore {
        if let explicitDataStore {
            return explicitDataStore
        }
        if let cachedPersistentDataStore {
            return cachedPersistentDataStore
        }

        let store = Profile.createDataStore(for: id)
        cachedPersistentDataStore = store
        return store
    }

    func prepareWebKitRuntime() {
        _ = dataStore
    }
    // Metadata (not yet persisted)
    var createdDate: Date = Date()
    var lastUsed: Date = Date()

    /// Whether this is an ephemeral/incognito profile (no disk persistence)
    var isEphemeral: Bool = false

    // Cached stats
    private(set) var cachedCookieCount: Int = 0
    private(set) var cachedRecordCount: Int = 0

    init(
        id: UUID = UUID(),
        name: String = "Default Profile"
    ) {
        self.id = id
        self.name = name
        self.explicitDataStore = nil
        super.init()
    }

    /// Initialize with a custom data store (used for ephemeral profiles)
    init(
        id: UUID = UUID(),
        name: String,
        dataStore: WKWebsiteDataStore
    ) {
        self.id = id
        self.name = name
        self.explicitDataStore = dataStore
        super.init()
    }

    // MARK: - Ephemeral Profile Factory
    /// Create a new ephemeral/incognito profile with non-persistent data store
    static func createEphemeral() -> Profile {
        let profile = Profile(
            id: UUID(),
            name: "Private",
            dataStore: .nonPersistent()
        )
        profile.isEphemeral = true
        RuntimeDiagnostics.emit("🔒 [Profile] Created ephemeral incognito profile: \(profile.id)")
        return profile
    }

    // MARK: - Data Store Creation
    /// Create the profile's Website Data Store. Tests and previews stay in memory;
    /// production uses a deterministic identifier that remains stable across launches.
    static func createDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        if RuntimeDiagnostics.usesEphemeralPlatformStores {
            return .nonPersistent()
        }
        let store = WKWebsiteDataStore(forIdentifier: profileId)
        if !store.isPersistent {
            RuntimeDiagnostics.emit("⚠️ [Profile] Created data store is not persistent for profile: \(profileId.uuidString)")
        } else {
            RuntimeDiagnostics.emit("✅ [Profile] Using persistent data store for profile \(profileId.uuidString) — id: \(store.identifier?.uuidString ?? "nil")")
        }
        return store
    }

    // MARK: - Validation & Stats
    @MainActor
    func refreshDataStoreStats(
        cleanupService: any SumiWebsiteDataCleanupServicing
    ) async {
        cachedCookieCount = await cleanupService
            .fetchCookies(in: dataStore)
            .count

        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        cachedRecordCount = await cleanupService
            .fetchWebsiteDataRecords(ofTypes: types, in: dataStore)
            .count
    }

    // MARK: - Cleanup
    @discardableResult
    func removePersistentDataStore(
        cleanupService: any SumiWebsiteDataCleanupServicing
    ) async -> Bool {
        guard !isEphemeral else { return true }
        guard persistentDataStoreWasRemoved == false else { return true }
        cachedPersistentDataStore = nil
        let removed = await cleanupService.removePersistentDataStore(
            forIdentifier: id
        )
        persistentDataStoreWasRemoved = removed
        return removed
    }

    /// Releases the ephemeral profile's non-persistent store ownership.
    /// Ephemeral profiles use `WKWebsiteDataStore.nonPersistent()` through the
    /// normal BrowserConfiguration path, so teardown must not synchronously scan
    /// or clear persistent WebKit storage.
    func destroyEphemeralDataStore() {
        guard isEphemeral else {
            RuntimeDiagnostics.emit("⚠️ [Profile] Cannot destroy data store: profile is not ephemeral")
            return
        }

        RuntimeDiagnostics.emit("🔒 [Profile] Released ephemeral data store for profile: \(id)")
    }
}
