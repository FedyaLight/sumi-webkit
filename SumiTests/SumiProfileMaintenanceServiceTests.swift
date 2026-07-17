import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiProfileMaintenanceServiceTests: XCTestCase {
    func testRuntimeSealFailureKeepsLogicalDeletionRecoveryHandoff() async throws {
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
        browserManager.browsingDataCleanupService.destructiveCleanupPreparer =
            AcceptingProfileDeletionCleanupPreparer()
        var profileExistedWhenRuntimeSealBegan = true
        var notices: [SumiProfileMaintenanceService.Notice] = []
        let noticePublished = expectation(description: "cleanup pending notice")

        SumiProfileMaintenanceService().deleteProfile(
            deleted,
            using: .init(
                currentProfile: { browserManager.currentProfile },
                profileManager: browserManager.profileManager,
                migrateProfileReferences: { _, _ in .committed },
                persistProfileReferences: { true },
                migrateBrowserProfileReferences: { _, _ in true },
                hasProfileReferences: { _ in false },
                sealProfileRuntime: { profileID in
                    profileExistedWhenRuntimeSealBegan = browserManager
                        .profileManager.profiles.contains {
                            $0.id == profileID
                        }
                    return false
                },
                browsingDataCleanupService: browserManager
                    .browsingDataCleanupService,
                websiteDataCleanupService: cleanupSpy,
                faviconService: browserManager.dataServices.faviconService,
                visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                permissionCleanupService: permissionHarness
                    .permissionCleanupService,
                applicationDataCleanupService:
                    ProfileApplicationDataCleanupService(
                        operations: .init(
                            clearHistory: { _ in },
                            clearBasicAuthCredentials: { _ in },
                            clearSiteDataPolicies: { _ in },
                            clearZoomPreferences: { _ in },
                            clearBoosts: { _ in },
                            clearAdblockZapperRules: { _ in },
                            clearExtensionPrivateData: { _ in }
                        )
                    ),
                showNotice: {
                    notices.append($0)
                    noticePublished.fulfill()
                }
            )
        )

        await fulfillment(of: [noticePublished], timeout: 2)

        XCTAssertFalse(profileExistedWhenRuntimeSealBegan)
        XCTAssertFalse(
            browserManager.profileManager.profiles.contains {
                $0.id == deleted.id
            }
        )
        let record = try XCTUnwrap(
            browserManager.profileReferenceAdmission.records().first {
                $0.snapshot.id == deleted.id
            }
        )
        XCTAssertEqual(record.phase, .logicallyDeleted)
        XCTAssertEqual(cleanupSpy.clearAllProfileDataCallCount, 0)
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 0)
        XCTAssertEqual(notices.last?.title, "Profile Deleted")
    }

    func testRejectedWebKitQuiescePreventsProfileAndStoreDeletion() async throws {
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
        var notices: [SumiProfileMaintenanceService.Notice] = []
        let service = SumiProfileMaintenanceService()

        service.deleteProfile(
            deleted,
            using: .init(
                currentProfile: { browserManager.currentProfile },
                profileManager: browserManager.profileManager,
                migrateProfileReferences: { _, _ in .committed },
                persistProfileReferences: { true },
                migrateBrowserProfileReferences: { _, _ in true },
                hasProfileReferences: { _ in false },
                sealProfileRuntime: { _ in true },
                browsingDataCleanupService:
                    browserManager.browsingDataCleanupService,
                websiteDataCleanupService: cleanupSpy,
                faviconService: browserManager.dataServices.faviconService,
                visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                permissionCleanupService: permissionHarness.permissionCleanupService,
                applicationDataCleanupService:
                    ProfileApplicationDataCleanupService(
                        operations: .init(
                            clearHistory: { _ in },
                            clearBasicAuthCredentials: { _ in },
                            clearSiteDataPolicies: { _ in },
                            clearZoomPreferences: { _ in },
                            clearBoosts: { _ in },
                            clearAdblockZapperRules: { _ in },
                            clearExtensionPrivateData: { _ in }
                        )
                    ),
                showNotice: { notices.append($0) }
            )
        )
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(preparer.callCount, 1)
        XCTAssertEqual(cleanupSpy.clearAllProfileDataCallCount, 0)
        XCTAssertEqual(cleanupSpy.removePersistentStoreCallCount, 0)
        XCTAssertTrue(
            browserManager.profileManager.profiles.contains {
                $0.id == deleted.id
            }
        )
        XCTAssertEqual(notices.last?.title, "Couldn't Delete Profile")
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
private final class AcceptingProfileDeletionCleanupPreparer:
    SumiDestructiveBrowsingDataCleanupPreparing {
    func performDestructiveDataCleanup(
        profileIDs: Set<UUID>,
        deletion: @escaping @MainActor () async -> Void
    ) async -> Bool {
        _ = profileIDs
        await deletion()
        return true
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
