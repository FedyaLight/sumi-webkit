import XCTest

@testable import Sumi

final class SumiPermissionSettlementDecisionBuilderTests: XCTestCase {
    func testPersistentApprovalUsesPersistentPersistenceWhenAvailable() {
        let pending = pendingQuery(
            permissionTypes: [.camera],
            availablePersistences: [.oneTime, .session, .persistent]
        )

        let decision = builder.decision(for: .approvePersistently, pending: pending)

        XCTAssertEqual(decision.outcome, .granted)
        XCTAssertEqual(decision.state, .allow)
        XCTAssertEqual(decision.persistence, .persistent)
        XCTAssertEqual(decision.source, .user)
        XCTAssertEqual(decision.reason, "approved-persistently")
        XCTAssertEqual(decision.permissionTypes, [.camera])
        XCTAssertEqual(decision.keys, pending.keys)
        XCTAssertEqual(decision.queryId, pending.query.id)
    }

    func testPersistentApprovalDowngradesToSessionForEphemeralQuery() {
        let pending = pendingQuery(
            permissionTypes: [.camera],
            availablePersistences: [.oneTime, .session, .persistent],
            isEphemeralProfile: true
        )

        let decision = builder.decision(for: .approvePersistently, pending: pending)

        XCTAssertEqual(decision.outcome, .granted)
        XCTAssertEqual(decision.persistence, .session)
        XCTAssertEqual(decision.reason, "approved-persistently-downgraded")
        XCTAssertTrue(decision.disablesPersistentAllow)
    }

    func testPersistentDenyIsIgnoredWhenPersistentPersistenceIsUnavailable() {
        let pending = pendingQuery(
            permissionTypes: [.camera],
            availablePersistences: [.oneTime, .session]
        )

        let decision = builder.decision(for: .denyPersistently, pending: pending)

        XCTAssertEqual(decision.outcome, .ignored)
        XCTAssertNil(decision.state)
        XCTAssertNil(decision.persistence)
        XCTAssertEqual(decision.source, .runtime)
        XCTAssertEqual(decision.reason, "persistent-deny-unavailable")
    }

    func testCancellationDecisionPreservesQueryContextWithoutPersistence() {
        let pending = pendingQuery(
            permissionTypes: [.camera, .microphone],
            availablePersistences: [.oneTime, .session],
            shouldOfferSystemSettings: true,
            disablesPersistentAllow: true
        )

        let decision = builder.decision(
            for: .cancel(reason: "test-cancelled"),
            pending: pending
        )

        XCTAssertEqual(decision.outcome, .cancelled)
        XCTAssertNil(decision.state)
        XCTAssertNil(decision.persistence)
        XCTAssertEqual(decision.source, .cancelled)
        XCTAssertEqual(decision.reason, "test-cancelled")
        XCTAssertEqual(decision.permissionTypes, [.camera, .microphone])
        XCTAssertEqual(decision.keys, pending.keys)
        XCTAssertEqual(decision.queryId, pending.query.id)
        XCTAssertTrue(decision.shouldOfferSystemSettings)
        XCTAssertTrue(decision.disablesPersistentAllow)
    }

    private var builder: SumiPermissionSettlementDecisionBuilder {
        SumiPermissionSettlementDecisionBuilder()
    }

    private func pendingQuery(
        permissionTypes: [SumiPermissionType],
        availablePersistences: Set<SumiPermissionPersistence>,
        isEphemeralProfile: Bool = false,
        shouldOfferSystemSettings: Bool = false,
        disablesPersistentAllow: Bool? = nil
    ) -> SumiPendingAuthorizationQuery {
        let profilePartitionId = isEphemeralProfile ? "ephemeral-profile-a" : "profile-a"
        let query = SumiPermissionAuthorizationQuery(
            id: "permission-query|tab-a:1|request-a",
            pageId: "tab-a:1",
            profilePartitionId: profilePartitionId,
            displayDomain: "example.com",
            requestingOrigin: sumiPermissionIntegrationOrigin(),
            topOrigin: sumiPermissionIntegrationOrigin(),
            permissionTypes: permissionTypes,
            presentationPermissionType: nil,
            availablePersistences: availablePersistences,
            systemAuthorizationSnapshots: [],
            policyReasons: ["test"],
            createdAt: sumiPermissionIntegrationNow,
            isEphemeralProfile: isEphemeralProfile,
            shouldOfferSystemSettings: shouldOfferSystemSettings,
            disablesPersistentAllow: disablesPersistentAllow ?? isEphemeralProfile
        )
        let keys = permissionTypes.map {
            sumiPermissionIntegrationKey(
                $0,
                profilePartitionId: profilePartitionId,
                isEphemeralProfile: isEphemeralProfile
            )
        }
        return SumiPendingAuthorizationQuery(
            query: query,
            primaryRequestId: "request-a",
            tabId: "tab-a",
            requestIds: ["request-a"],
            keys: keys
        )
    }
}
