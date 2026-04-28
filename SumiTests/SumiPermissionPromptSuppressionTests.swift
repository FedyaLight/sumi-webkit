import XCTest

@testable import Sumi

final class SumiPermissionPromptSuppressionTests: XCTestCase {
    func testSuppressedNotificationAfterDismissalResolvesDefault() {
        let key = antiAbuseKey(.notifications)
        let suppression = SumiPermissionPromptSuppression(
            kind: .cooldown,
            trigger: .dismissal,
            key: key,
            until: Date(timeIntervalSince1970: 1_800_000_600),
            reason: "dismissal-cooldown"
        )
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .suppressed,
            state: .ask,
            persistence: nil,
            source: .cooldown,
            reason: suppression.reason,
            permissionTypes: [.notifications],
            keys: [key],
            promptSuppression: suppression
        )

        XCTAssertEqual(
            SumiWebNotificationDecisionMapper.permissionState(for: decision),
            .default
        )
    }

    func testSuppressedNotificationAfterExplicitDenyResolvesDenied() {
        let key = antiAbuseKey(.notifications)
        let suppression = SumiPermissionPromptSuppression(
            kind: .cooldown,
            trigger: .explicitDeny,
            key: key,
            until: Date(timeIntervalSince1970: 1_800_000_600),
            reason: "explicit-deny-cooldown"
        )
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .suppressed,
            state: .ask,
            persistence: nil,
            source: .cooldown,
            reason: suppression.reason,
            permissionTypes: [.notifications],
            keys: [key],
            promptSuppression: suppression
        )

        XCTAssertEqual(
            SumiWebNotificationDecisionMapper.permissionState(for: decision),
            .denied
        )
    }

    func testSuppressedExternalSchemeBlocksWithoutOpening() {
        let key = antiAbuseKey(.externalScheme("zoommtg"))
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .suppressed,
            state: .ask,
            persistence: nil,
            source: .cooldown,
            reason: "dismissal-cooldown",
            permissionTypes: [.externalScheme("zoommtg")],
            keys: [key]
        )
        let request = SumiExternalSchemePermissionRequest(
            id: "external-a",
            path: .navigationResponder,
            targetURL: URL(string: "zoommtg://join")!,
            sourceURL: URL(string: "https://example.com")!,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            userActivation: .navigationAction,
            isMainFrame: true,
            isRedirectChain: false
        )

        XCTAssertEqual(
            SumiExternalSchemeDecisionMapper.resultKind(for: decision, request: request),
            .blockedPendingUI
        )
    }
}
