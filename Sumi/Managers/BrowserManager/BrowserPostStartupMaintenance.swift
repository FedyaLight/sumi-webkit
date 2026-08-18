import Foundation
import WebKit

@MainActor
enum BrowserPostStartupMaintenance {
    private static var storageTask: Task<Void, Never>?

    static func start(
        history: HistoryManager,
        bookmarks: SumiBookmarkManager,
        profiles: [Profile],
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        database: SumiDatabase,
        foregroundProfileID: @escaping @MainActor () -> UUID?
    ) {
        startStorageMaintenanceIfNeeded(
            profiles: profiles,
            cleanupService: websiteDataCleanupService,
            database: database,
            foregroundProfileID: foregroundProfileID
        )
        guard history.start() else { return }
        bookmarks.startDeferredFaviconSync()

        let stagingRoot = SumiImportBulkStagingStore.defaultRootDirectory()
        Task.detached(priority: .utility) {
            guard Task.isCancelled == false else { return }
            SumiImportBulkStagingStore(rootDirectory: stagingRoot)
                .sweepOrphans()
        }
    }

    private static func startStorageMaintenanceIfNeeded(
        profiles: [Profile],
        cleanupService: any SumiWebsiteDataCleanupServicing,
        database: SumiDatabase,
        foregroundProfileID: @escaping @MainActor () -> UUID?
    ) {
        guard RuntimeDiagnostics.usesEphemeralPlatformStores == false,
              storageTask == nil
        else {
            return
        }

        storageTask = Task {
            defer { storageTask = nil }
            do {
                _ = try await SumiHTTPDiskCacheUpgrade.runIfNeeded(
                    profiles: profiles,
                    cleanupService: cleanupService,
                    database: database
                )
                let platformCleanupService = SumiWebsiteDataCleanupService()
                let liveWebsiteDataStoreIDs = Set(profiles.map(\.id))
                _ = try await SumiOrphanIdentifierBatch.runIfNeeded(
                    documentKey:
                        "local-installation-storage.website-data-store-orphans.v1",
                    batchSize: 64,
                    liveIdentifiers: liveWebsiteDataStoreIDs,
                    database: database,
                    fetchIdentifiers: {
                        await SumiWebsiteDataCleanupService
                            .fetchPersistentDataStoreIdentifiers()
                    },
                    removeIdentifier: { identifier in
                        await platformCleanupService.removePersistentDataStore(
                            forIdentifier: identifier
                        )
                    }
                )
                let liveExtensionControllerIDs = try
                    SumiOrphanWebExtensionControllerReclaimer
                    .liveControllerIdentifiers(database: database)
                if let legacyControllerID =
                    ExtensionControllerIdentifierOwner.legacyIdentifier,
                   liveExtensionControllerIDs.contains(legacyControllerID) == false {
                    try WebExtensionStorageCleanupStore(
                        controllerStorageId: legacyControllerID
                    ).deleteControllerStorageDirectory()
                }
                ExtensionControllerIdentifierOwner.removeLegacyIdentifier()
                _ = try await SumiOrphanWebExtensionControllerReclaimer.runIfNeeded(
                    liveControllerIDs: liveExtensionControllerIDs,
                    database: database,
                    fetchIdentifiers: {
                        WebExtensionStorageCleanupStore
                            .controllerStorageIdentifiers()
                    },
                    removeIdentifier: { identifier in
                        do {
                            try WebExtensionStorageCleanupStore(
                                controllerStorageId: identifier
                            ).deleteControllerStorageDirectory()
                            return true
                        } catch {
                            return false
                        }
                    }
                )
                SumiHTTPDiskCacheBudget.recordActivation(
                    profileID: foregroundProfileID(),
                    database: database
                )
                _ = try await SumiHTTPDiskCacheBudget.runIfNeeded(
                    profiles: profiles,
                    foregroundProfileID: foregroundProfileID,
                    database: database,
                    observe: { profile in
                        await SumiWebKitDiskCacheSizeObserver.diskCacheBytes(
                            in: profile.dataStore
                        )
                    },
                    clearDiskCache: { profile in
                        await cleanupService.removeWebsiteData(
                            ofTypes: [WKWebsiteDataTypeDiskCache],
                            modifiedSince: .distantPast,
                            in: profile.dataStore
                        )
                    }
                )
            } catch {
                RuntimeDiagnostics.emit(
                    "[StorageMaintenance] Post-startup storage maintenance failed: \(error)"
                )
            }
        }
    }
}

@MainActor
enum SumiHTTPDiskCacheUpgrade {
    private static let documentKey =
        "local-installation-storage.http-disk-cache-reset.v1"
    private static let completedMarker = Data("complete".utf8)

    @discardableResult
    static func runIfNeeded(
        profiles: [Profile],
        cleanupService: any SumiWebsiteDataCleanupServicing,
        database: SumiDatabase
    ) async throws -> Bool {
        let completed = try database.read {
            try $0.documents.data(forKey: documentKey) == completedMarker
        }
        guard completed == false else { return false }

        for profile in profiles where profile.isEphemeral == false {
            await cleanupService.removeWebsiteData(
                ofTypes: [WKWebsiteDataTypeDiskCache],
                modifiedSince: .distantPast,
                in: profile.dataStore
            )
        }
        try database.transaction {
            try $0.documents.save(completedMarker, forKey: documentKey)
        }
        return true
    }
}
