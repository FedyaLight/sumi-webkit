//
//  Profile.swift
//  Sumi
//
//  Runtime profile model representing a browsing persona.
//  Each Profile now owns a persistent, isolated WKWebsiteDataStore
//  to provide strong data separation across profiles.
//

import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class Profile: NSObject, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    @ObservationIgnored private let explicitDataStore: WKWebsiteDataStore?
    @ObservationIgnored private var cachedPersistentDataStore: WKWebsiteDataStore?
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
        name: String = "Default Profile",
        icon: String = "person.crop.circle"
    ) {
        self.id = id
        self.name = name
        self.icon = SumiPersistentGlyph.normalizedProfileIconValue(icon)
        self.explicitDataStore = nil
        super.init()
    }

    /// Initialize with a custom data store (used for ephemeral profiles)
    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        dataStore: WKWebsiteDataStore
    ) {
        self.id = id
        self.name = name
        self.icon = SumiPersistentGlyph.normalizedProfileIconValue(icon)
        self.explicitDataStore = dataStore
        super.init()
    }

    // MARK: - Ephemeral Profile Factory
    /// Create a new ephemeral/incognito profile with non-persistent data store
    static func createEphemeral() -> Profile {
        let profile = Profile(
            id: UUID(),
            name: "Incognito",
            icon: "eye.slash",
            dataStore: .nonPersistent()
        )
        profile.isEphemeral = true
        RuntimeDiagnostics.emit("🔒 [Profile] Created ephemeral incognito profile: \(profile.id)")
        return profile
    }

    // MARK: - Data Store Creation
    /// Create a persistent, profile-specific WKWebsiteDataStore for the given profile ID.
    /// Uses a deterministic identifier so stores remain stable across launches.
    private static func createDataStore(for profileId: UUID) -> WKWebsiteDataStore {
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
    func refreshDataStoreStats() async {
        cachedCookieCount = await SumiWebsiteDataCleanupService.shared
            .fetchCookies(in: dataStore)
            .count

        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        cachedRecordCount = await SumiWebsiteDataCleanupService.shared
            .fetchWebsiteDataRecords(ofTypes: types, in: dataStore)
            .count
    }

    // MARK: - Cleanup
    func clearAllData() async {
        await SumiWebsiteDataCleanupService.shared.clearAllProfileWebsiteData(in: dataStore)
        await refreshDataStoreStats()
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
