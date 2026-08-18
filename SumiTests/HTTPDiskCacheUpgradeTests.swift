import Foundation
import XCTest

@testable import Sumi

@MainActor
final class HTTPDiskCacheUpgradeTests: XCTestCase {
    func testUpgradeRunsOnceWithoutChangingWebsiteDataIsolation() async throws {
        let database = try SumiDatabase.inMemory()
        let cleanupService = SumiWebsiteDataCleanupService()
        let firstProfile = Profile(name: "First")
        let secondProfile = Profile(name: "Second")
        let firstCookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "account",
            .value: "first",
        ]))
        let secondCookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "account",
            .value: "second",
        ]))
        await firstProfile.dataStore.httpCookieStore.setCookie(firstCookie)
        await secondProfile.dataStore.httpCookieStore.setCookie(secondCookie)

        XCTAssertFalse(firstProfile.dataStore.isPersistent)
        XCTAssertFalse(secondProfile.dataStore.isPersistent)
        let firstRun = try await SumiHTTPDiskCacheUpgrade.runIfNeeded(
            profiles: [firstProfile, secondProfile],
            clearDiskCaches: { profiles in
                for profile in profiles where profile.isEphemeral == false {
                    await cleanupService.removeWebsiteData(
                        ofTypes: [WKWebsiteDataTypeDiskCache],
                        modifiedSince: .distantPast,
                        in: profile.dataStore
                    )
                }
                return true
            },
            database: database
        )
        let secondRun = try await SumiHTTPDiskCacheUpgrade.runIfNeeded(
            profiles: [firstProfile, secondProfile],
            clearDiskCaches: { _ in true },
            database: database
        )
        XCTAssertTrue(firstRun)
        XCTAssertFalse(secondRun)
        XCTAssertFalse(firstProfile.dataStore === secondProfile.dataStore)
        let firstCookies = await cleanupService.fetchCookies(
            in: firstProfile.dataStore
        )
        let secondCookies = await cleanupService.fetchCookies(
            in: secondProfile.dataStore
        )
        XCTAssertEqual(firstCookies.map(\.value), ["first"])
        XCTAssertEqual(secondCookies.map(\.value), ["second"])
    }

    func testUpgradeRetriesWhenDestructiveCleanupIsNotAdmitted() async throws {
        let database = try SumiDatabase.inMemory()
        let profile = Profile(name: "Regular")

        let blocked = try await SumiHTTPDiskCacheUpgrade.runIfNeeded(
            profiles: [profile],
            clearDiskCaches: { _ in false },
            database: database
        )
        let retried = try await SumiHTTPDiskCacheUpgrade.runIfNeeded(
            profiles: [profile],
            clearDiskCaches: { _ in true },
            database: database
        )

        XCTAssertFalse(blocked)
        XCTAssertTrue(retried)
    }
}
