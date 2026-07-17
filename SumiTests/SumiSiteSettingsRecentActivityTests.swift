import XCTest

@testable import Sumi
import SumiDomain

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

    func testRetiredProfileActivityCannotBeRecreatedAndRetainedProfileRemainsWritable() {
        let store = SumiPermissionRecentActivityStore()
        let targetKey = activityKey(
            profileID: "target-profile",
            host: "target.example"
        )
        let retainedKey = activityKey(
            profileID: "retained-profile",
            host: "retained.example"
        )
        store.recordSettingsChange(
            displayDomain: "target.example",
            key: targetKey,
            state: .allow
        )
        store.recordSettingsChange(
            displayDomain: "retained.example",
            key: retainedKey,
            state: .allow
        )

        store.deleteProfileData(profilePartitionId: "target-profile")
        store.recordSettingsChange(
            displayDomain: "target.example",
            key: targetKey,
            state: .deny
        )
        store.recordSettingsChange(
            displayDomain: "retained.example",
            key: retainedKey,
            state: .deny
        )

        XCTAssertTrue(
            store.records(
                profilePartitionId: "target-profile",
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(
            store.records(
                profilePartitionId: "retained-profile",
                isEphemeralProfile: false
            ).count,
            2
        )
    }

    private func activityKey(
        profileID: String,
        host: String
    ) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://\(host)")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: profileID
        )
    }
}
