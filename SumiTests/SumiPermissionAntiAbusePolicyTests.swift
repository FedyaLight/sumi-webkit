import XCTest

@testable import Sumi

final class SumiPermissionAntiAbusePolicyTests: XCTestCase {
    private let policy = SumiPermissionAntiAbusePolicy()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstDismissStartsTenMinuteCooldown() {
        let key = antiAbuseKey(.camera)
        let events = [
            event(.userDismissed, key: key, at: now)
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(suppression?.kind, .cooldown)
        XCTAssertEqual(suppression?.trigger, .dismissal)
        XCTAssertEqual(
            suppression?.until,
            now.addingTimeInterval(SumiPermissionPromptCooldown.firstDismissCooldown)
        )
    }

    func testCooldownExpiryAllowsPromptAgain() {
        let key = antiAbuseKey(.camera)
        let events = [
            event(.userDismissed, key: key, at: now)
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(SumiPermissionPromptCooldown.firstDismissCooldown + 1)
        )

        XCTAssertNil(suppression)
    }

    func testSecondDismissWithinWindowCreatesLongerCooldown() {
        let key = antiAbuseKey(.camera)
        let secondDismiss = now.addingTimeInterval(60)
        let events = [
            event(.userDismissed, key: key, at: now),
            event(.userDismissed, key: key, at: secondDismiss),
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: secondDismiss.addingTimeInterval(60)
        )

        XCTAssertEqual(suppression?.kind, .cooldown)
        XCTAssertEqual(suppression?.reason, "repeated-dismissal-cooldown")
        XCTAssertEqual(
            suppression?.until,
            secondDismiss.addingTimeInterval(SumiPermissionPromptCooldown.secondDismissCooldown)
        )
    }

    func testThirdDismissCreatesQuietEmbargo() {
        let key = antiAbuseKey(.camera)
        let thirdDismiss = now.addingTimeInterval(120)
        let events = [
            event(.userDismissed, key: key, at: now),
            event(.userDismissed, key: key, at: now.addingTimeInterval(60)),
            event(.userDismissed, key: key, at: thirdDismiss),
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: thirdDismiss.addingTimeInterval(60)
        )

        XCTAssertEqual(suppression?.kind, .embargo)
        XCTAssertEqual(suppression?.reason, "repeated-dismissal-embargo")
    }

    func testAllowClearsPriorSuppressionWindowForPolicyEvaluation() {
        let key = antiAbuseKey(.camera)
        let events = [
            event(.userDismissed, key: key, at: now),
            event(.userAllowed, key: key, at: now.addingTimeInterval(60)),
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(120)
        )

        XCTAssertNil(suppression)
    }

    func testNavigationCancellationDoesNotCountAsDismissal() {
        let key = antiAbuseKey(.camera)
        let events = [
            event(.requestCancelledByNavigation, key: key, at: now)
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(60)
        )

        XCTAssertNil(suppression)
    }

    func testDifferentPermissionOriginAndProfileAreIndependent() {
        let key = antiAbuseKey(.camera)
        let otherPermission = antiAbuseKey(.microphone)
        let otherOrigin = antiAbuseKey(
            .camera,
            requestingOrigin: SumiPermissionOrigin(string: "https://other.example")
        )
        let otherProfile = antiAbuseKey(.camera, profile: "profile-b")
        let events = [
            event(.userDismissed, key: otherPermission, at: now),
            event(.userDismissed, key: otherOrigin, at: now),
            event(.userDismissed, key: otherProfile, at: now),
        ]

        let suppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(60)
        )

        XCTAssertNil(suppression)
    }

    func testSystemBlockedCooldownIsSeparateFromUserDeny() {
        let key = antiAbuseKey(.camera)
        let events = [
            event(.systemBlocked, key: key, at: now)
        ]

        let promptSuppression = policy.suppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(60)
        )
        let systemSuppression = policy.systemBlockedSuppression(
            for: key,
            events: events,
            now: now.addingTimeInterval(60)
        )

        XCTAssertNil(promptSuppression)
        XCTAssertEqual(systemSuppression?.trigger, .systemBlocked)
    }
}

func event(
    _ type: SumiPermissionAntiAbuseEvent.EventType,
    key: SumiPermissionKey,
    at date: Date
) -> SumiPermissionAntiAbuseEvent {
    SumiPermissionAntiAbuseEvent(type: type, key: key, createdAt: date)
}

func antiAbuseKey(
    _ type: SumiPermissionType,
    requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com/path?token=1#frag"),
    topOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
    profile: String = "profile-a",
    isEphemeral: Bool = false
) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: requestingOrigin,
        topOrigin: topOrigin,
        permissionType: type,
        profilePartitionId: profile,
        transientPageId: "page-a",
        isEphemeralProfile: isEphemeral
    )
}
