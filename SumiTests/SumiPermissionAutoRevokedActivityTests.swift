import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionAutoRevokedActivityTests: XCTestCase {
    func testCleanupRecordsAutoRevokedRecentActivity() async throws {
        let harness = try CleanupHarness()
        let key = harness.key(.camera)
        try await harness.store.setDecision(
            for: key,
            decision: harness.decision(.allow, updatedAt: harness.oldDate)
        )

        let result = await harness.runEnabled()
        let records = harness.recentActivityStore.records(
            profilePartitionId: harness.profile.profilePartitionId,
            isEphemeralProfile: false
        )

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(records.first?.action, .autoRevoked)
    }
}
