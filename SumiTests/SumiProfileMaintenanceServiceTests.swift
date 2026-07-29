import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiProfileMaintenanceServiceTests: XCTestCase {
    func testLastProfileRetirementCreatesEmptyDefaultWithoutResettingPreferences()
        async throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let suiteName =
            "SumiProfileMaintenanceServiceTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("keep-me", forKey: "browser.appearance")
        let permissionHarness = try SiteSettingsRepositoryHarness(
            profile: deleted,
            userDefaults: preferences
        )
        let cleanupSpy = ProfileMaintenanceWebsiteDataCleanupSpy()
        var migratedFallbackID: UUID?

        let result = await SumiProfileMaintenanceService().retireProfile(
            deleted,
            using: .init(
                profileManager: browserManager.profileManager,
                migrateReferences: { _, fallback in
                    migratedFallbackID = fallback.id
                    return true
                },
                sealProfileRuntime: { _ in true },
                cleanupDependencies: cleanupDependencies(
                    browserManager: browserManager,
                    permissionHarness: permissionHarness,
                    websiteDataCleanup: cleanupSpy
                )
            )
        )

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(browserManager.profileManager.profiles.count, 1)
        let replacement = try XCTUnwrap(
            browserManager.profileManager.profiles.first
        )
        XCTAssertNotEqual(replacement.id, deleted.id)
        XCTAssertEqual(replacement.name, "Default")
        XCTAssertEqual(migratedFallbackID, replacement.id)
        XCTAssertEqual(
            preferences.string(forKey: "browser.appearance"),
            "keep-me"
        )
        XCTAssertEqual(cleanupSpy.clearAllProfileDataCallCount, 0)
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 1)
    }

    func testFailedLastProfileReservationRollsBackProvisionalDefault()
        async throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let permissionHarness = try SiteSettingsRepositoryHarness(
            profile: deleted
        )
        let cleanupSpy = ProfileMaintenanceWebsiteDataCleanupSpy()
        let activeLease = try browserManager.profileReferenceAdmission
            .beginReferenceMutation(to: [deleted.id])
        defer {
            XCTAssertTrue(
                browserManager.profileReferenceAdmission
                    .endReferenceMutation(activeLease)
            )
        }

        let result = await SumiProfileMaintenanceService().retireProfile(
            deleted,
            using: .init(
                profileManager: browserManager.profileManager,
                migrateReferences: { _, _ in true },
                sealProfileRuntime: { _ in true },
                cleanupDependencies: cleanupDependencies(
                    browserManager: browserManager,
                    permissionHarness: permissionHarness,
                    websiteDataCleanup: cleanupSpy
                )
            )
        )

        guard case .failed = result else {
            return XCTFail("Expected reservation failure")
        }
        XCTAssertEqual(
            browserManager.profileManager.profiles.map(\.id),
            [deleted.id]
        )
        XCTAssertTrue(
            browserManager.profileReferenceAdmission.records().isEmpty
        )
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 0)
    }

    func testRuntimeSealFailureLeavesProfileVisibleForRetry() async throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        browserManager.currentProfile = fallback
        let permissionHarness = try SiteSettingsRepositoryHarness(
            profile: deleted
        )
        let cleanupSpy = ProfileMaintenanceWebsiteDataCleanupSpy()
        var profileExistedWhenRuntimeSealBegan = false

        let result = await SumiProfileMaintenanceService().retireProfile(
            deleted,
            fallback: fallback,
            using: .init(
                profileManager: browserManager.profileManager,
                migrateReferences: { _, _ in true },
                sealProfileRuntime: { profileID in
                    profileExistedWhenRuntimeSealBegan = browserManager
                        .profileManager.profiles.contains {
                            $0.id == profileID
                    }
                    return false
                },
                cleanupDependencies: ProfileRetirementCleanupDependencies(
                    websiteDataCleanupService: cleanupSpy,
                    faviconService: browserManager.dataServices.faviconService,
                    visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                    permissionCleanupService: permissionHarness
                        .permissionCleanupService,
                    applicationDataCleanupService:
                        ProfileApplicationDataCleanupService(
                        operations: .init(
                            clearBasicAuthCredentials: { _ in },
                            clearSiteDataPolicies: { _ in },
                            clearZoomPreferences: { _ in },
                            clearBoosts: { _ in },
                            clearAdblockZapperRules: { _ in },
                            clearExtensionPrivateData: { _ in }
                        )
                    )
                )
            )
        )

        XCTAssertEqual(result, .migrationPending)
        XCTAssertTrue(profileExistedWhenRuntimeSealBegan)
        XCTAssertTrue(
            browserManager.profileManager.profiles.contains {
                $0.id == deleted.id
            }
        )
        XCTAssertEqual(
            browserManager.profileManager.retiringProfileIDs,
            [deleted.id]
        )
        let record = try XCTUnwrap(
            browserManager.profileReferenceAdmission.records().first {
                $0.snapshot.id == deleted.id
            }
        )
        XCTAssertEqual(record.phase, .migratingReferences)
        XCTAssertEqual(cleanupSpy.clearAllProfileDataCallCount, 0)
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 0)
    }

    func testRetiredRuntimeDoesNotRunSecondWebKitQuiesce() async throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        browserManager.currentProfile = fallback
        let permissionHarness = try SiteSettingsRepositoryHarness(profile: deleted)

        let cleanupSpy = ProfileMaintenanceWebsiteDataCleanupSpy()
        let preparer = RejectingProfileDeletionCleanupPreparer()
        browserManager.browsingDataCleanupService.destructiveCleanupPreparer =
            preparer
        let service = SumiProfileMaintenanceService()

        let result = await service.retireProfile(
            deleted,
            fallback: fallback,
            using: .init(
                profileManager: browserManager.profileManager,
                migrateReferences: { _, _ in true },
                sealProfileRuntime: { _ in true },
                cleanupDependencies: ProfileRetirementCleanupDependencies(
                    websiteDataCleanupService: cleanupSpy,
                    faviconService: browserManager.dataServices.faviconService,
                    visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                    permissionCleanupService:
                        permissionHarness.permissionCleanupService,
                    applicationDataCleanupService:
                        ProfileApplicationDataCleanupService(
                        operations: .init(
                            clearBasicAuthCredentials: { _ in },
                            clearSiteDataPolicies: { _ in },
                            clearZoomPreferences: { _ in },
                            clearBoosts: { _ in },
                            clearAdblockZapperRules: { _ in },
                            clearExtensionPrivateData: { _ in }
                        )
                    )
                )
            )
        )

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(preparer.callCount, 0)
        XCTAssertEqual(cleanupSpy.clearAllProfileDataCallCount, 0)
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 1)
        XCTAssertFalse(
            browserManager.profileManager.profiles.contains {
                $0.id == deleted.id
            }
        )
    }

    private func cleanupDependencies(
        browserManager: BrowserManager,
        permissionHarness: SiteSettingsRepositoryHarness,
        websiteDataCleanup: any SumiWebsiteDataCleanupServicing
    ) -> ProfileRetirementCleanupDependencies {
        ProfileRetirementCleanupDependencies(
            websiteDataCleanupService: websiteDataCleanup,
            faviconService: browserManager.dataServices.faviconService,
            visitedLinkStore: browserManager.dataServices.visitedLinkStore,
            permissionCleanupService: permissionHarness
                .permissionCleanupService,
            applicationDataCleanupService:
                ProfileApplicationDataCleanupService(
                    operations: .init(
                        clearBasicAuthCredentials: { _ in },
                        clearSiteDataPolicies: { _ in },
                        clearZoomPreferences: { _ in },
                        clearBoosts: { _ in },
                        clearAdblockZapperRules: { _ in },
                        clearExtensionPrivateData: { _ in }
                    )
                )
        )
    }
}

@MainActor
private final class RejectingProfileDeletionCleanupPreparer:
    SumiDestructiveBrowsingDataCleanupPreparing {
    private(set) var callCount = 0

    func performDestructiveDataCleanup(
        profileIDs: Set<UUID>,
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        callCount += 1
        return false
    }
}

@MainActor
private final class ProfileMaintenanceWebsiteDataCleanupSpy:
    SumiWebsiteDataCleanupServicing {
    private(set) var clearAllProfileDataCallCount = 0
    private(set) var removePersistentStoreCallCount = 0

    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        []
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func clearAllProfileWebsiteData(
        in dataStore: WKWebsiteDataStore
    ) async {
        clearAllProfileDataCallCount += 1
    }

    func removePersistentDataStore(forIdentifier identifier: UUID) async
        -> Bool {
        removePersistentStoreCallCount += 1
        return true
    }

    func prunePersistentDataStores(
        keeping identifiersToKeep: Set<UUID>
    ) async -> [UUID] {
        []
    }
}
