import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiProfileMaintenanceServiceTests: XCTestCase {
    func testRejectedWebKitQuiescePreventsProfileAndStoreDeletion() async {
        let browserManager = BrowserManager()
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        browserManager.profileManager.profiles = [deleted, fallback]
        browserManager.currentProfile = fallback

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
                browsingDataCleanupService:
                    browserManager.browsingDataCleanupService,
                websiteDataCleanupService: cleanupSpy,
                faviconService: browserManager.dataServices.faviconService,
                visitedLinkStore: browserManager.dataServices.visitedLinkStore,
                permissionCleanupService: nil,
                showNotice: { notices.append($0) },
                switchToProfile: { _ in }
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
