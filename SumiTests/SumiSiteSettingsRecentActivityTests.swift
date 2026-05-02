import XCTest

@testable import Sumi

@MainActor
final class SumiSiteSettingsRecentActivityTests: XCTestCase {
    func testSettingsDecisionActivityAppearsForCurrentProfile() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let otherProfile = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        harness.recentStore.recordSettingsChange(
            displayDomain: "example.com",
            key: harness.key(.microphone),
            state: .allow,
            now: Date(timeIntervalSince1970: 100)
        )
        harness.recentStore.recordSettingsChange(
            displayDomain: "other.example",
            key: SumiPermissionKey(
                requestingOrigin: SumiPermissionOrigin(string: "https://other.example"),
                topOrigin: SumiPermissionOrigin(string: "https://other.example"),
                permissionType: .camera,
                profilePartitionId: otherProfile
            ),
            state: .deny,
            now: Date(timeIntervalSince1970: 200)
        )

        let items = harness.repository.recentActivity(profile: harness.profileContext)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "example.com - Microphone allowed")
    }

    func testBlockedPopupExternalSchemeAndSystemBlockedActivityAppear() async throws {
        let harness = try SiteSettingsRepositoryHarness()
        let origin = SumiPermissionOrigin(string: "https://example.com")
        harness.blockedPopupStore.record(
            SumiBlockedPopupRecord(
                id: "popup-1",
                tabId: "tab-a",
                pageId: "tab-a:1",
                requestingOrigin: origin,
                topOrigin: origin,
                targetURL: URL(string: "https://example.com/window"),
                sourceURL: URL(string: "https://example.com"),
                lastBlockedAt: Date(timeIntervalSince1970: 100),
                reason: .blockedByDefault,
                profilePartitionId: harness.profile.id.uuidString,
                isEphemeralProfile: false,
                attemptCount: 1
            )
        )
        harness.externalSchemeStore.record(
            SumiExternalSchemeAttemptRecord(
                id: "external-1",
                tabId: "tab-a",
                pageId: "tab-a:1",
                requestingOrigin: origin,
                topOrigin: origin,
                scheme: "mailto",
                redactedTargetURLString: "mailto:...",
                lastAttemptAt: Date(timeIntervalSince1970: 101),
                result: .opened,
                reason: "opened",
                profilePartitionId: harness.profile.id.uuidString,
                isEphemeralProfile: false,
                attemptCount: 1
            )
        )
        harness.indicatorStore.record(
            SumiPermissionIndicatorEventRecord(
                id: "system-1",
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com",
                permissionTypes: [.notifications],
                category: .systemBlocked,
                visualStyle: .systemWarning,
                priority: .systemBlockedSensitive,
                requestingOrigin: origin,
                topOrigin: origin,
                profilePartitionId: harness.profile.id.uuidString,
                isEphemeralProfile: false,
                createdAt: Date(timeIntervalSince1970: 102)
            )
        )

        let titles = harness.repository.recentActivity(
            profile: harness.profileContext,
            limit: 10
        ).map(\.title)

        XCTAssertTrue(titles.contains("example.com - Pop-ups and redirects blocked popup"))
        XCTAssertTrue(titles.contains("example.com - External app links opened external app"))
        XCTAssertTrue(titles.contains("example.com - Notifications blocked by macOS settings"))
    }

    func testEmptyRecentActivityIsStable() async throws {
        let harness = try SiteSettingsRepositoryHarness()

        XCTAssertEqual(harness.repository.recentActivity(profile: harness.profileContext), [])
    }
}
