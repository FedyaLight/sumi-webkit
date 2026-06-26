import XCTest

@testable import Sumi

final class SumiPermissionCoordinatorPendingQueryTests: XCTestCase {
    func testQueryPermissionStateDoesNotRegisterActiveQuery() async {
        let coordinator = makeCoordinator()

        let decision = await coordinator.queryPermissionState(
            pendingQueryContext(permissionTypes: [.camera], id: "camera-state-query")
        )

        XCTAssertEqual(decision.outcome, .promptRequired)
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeQuery)
        let snapshot = await coordinator.stateSnapshot()
        XCTAssertTrue(snapshot.activeQueriesByPageId.isEmpty)
        XCTAssertTrue(snapshot.queueCountByPageId.isEmpty)
    }

    func testCancellingCoalescedRequestKeepsPrimaryQueryActive() async {
        let coordinator = makeCoordinator()
        let primaryContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-primary")
        let primaryTask = Task {
            await coordinator.requestPermission(primaryContext)
        }
        let primaryQuery = await waitForActiveQuery(coordinator)

        let coalescedContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-coalesced")
        let coalescedTask = Task {
            await coordinator.requestPermission(coalescedContext)
        }
        await waitForCoalescedRequest(coordinator, requestId: "camera-coalesced")

        let cancellation = await coordinator.cancel(
            requestId: "camera-coalesced",
            reason: "test-coalesced-cancelled"
        )
        XCTAssertEqual(cancellation.outcome, .cancelled)

        let coalescedDecision = await coalescedTask.value
        XCTAssertEqual(coalescedDecision.outcome, .cancelled)
        XCTAssertEqual(coalescedDecision.reason, "test-coalesced-cancelled")
        let activeAfterCoalescedCancellation = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertEqual(activeAfterCoalescedCancellation?.id, primaryQuery.id)

        await coordinator.approveOnce(primaryQuery.id)
        let primaryDecision = await primaryTask.value
        XCTAssertEqual(primaryDecision.outcome, .granted)
        let activeAfterPrimaryApproval = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeAfterPrimaryApproval)
    }

    func testSettlingActiveQueryPromotesQueuedQueryInSnapshot() async {
        let coordinator = makeCoordinator()
        let firstContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-primary")
        let firstTask = Task {
            await coordinator.requestPermission(firstContext)
        }
        let firstQuery = await waitForActiveQuery(coordinator)

        let secondContext = pendingQueryContext(permissionTypes: [.microphone], id: "microphone-queued")
        let secondTask = Task {
            await coordinator.requestPermission(secondContext)
        }
        await waitForQueueCount(coordinator, pageId: "tab-a:1", count: 1)

        await coordinator.approveOnce(firstQuery.id)
        let firstDecision = await firstTask.value
        XCTAssertEqual(firstDecision.outcome, .granted)

        let promotedQuery = await waitForActiveQuery(coordinator) { query in
            query.id != firstQuery.id
        }
        XCTAssertEqual(promotedQuery.permissionTypes, [.microphone])
        let promotedSnapshot = await coordinator.stateSnapshot()
        XCTAssertEqual(promotedSnapshot.activeQueriesByPageId["tab-a:1"]?.id, promotedQuery.id)

        await coordinator.dismiss(promotedQuery.id)
        let secondDecision = await secondTask.value
        XCTAssertEqual(secondDecision.outcome, .dismissed)
        let activeAfterDismissal = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertNil(activeAfterDismissal)
    }

    private func makeCoordinator() -> SumiPermissionCoordinator {
        SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(
                    states: sumiPermissionIntegrationAuthorizedSystemStates()
                )
            ),
            persistentStore: SumiPermissionIntegrationStore(),
            now: { sumiPermissionIntegrationNow }
        )
    }

    private func pendingQueryContext(
        permissionTypes: [SumiPermissionType],
        id: String
    ) -> SumiPermissionSecurityContext {
        sumiPermissionIntegrationContext(
            permissionTypes,
            id: id,
            tabId: "tab-a",
            pageId: "tab-a:1"
        )
    }

    private func waitForActiveQuery(
        _ coordinator: SumiPermissionCoordinator,
        where isMatch: (SumiPermissionAuthorizationQuery) -> Bool = { _ in true },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SumiPermissionAuthorizationQuery {
        for _ in 0..<200 {
            if let query = await coordinator.activeQuery(forPageId: "tab-a:1"),
               isMatch(query)
            {
                return query
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for active permission query", file: file, line: line)
        fatalError("Timed out waiting for active permission query")
    }

    private func waitForCoalescedRequest(
        _ coordinator: SumiPermissionCoordinator,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            let snapshot = await coordinator.stateSnapshot()
            if case .queryCoalesced(_, let coalescedRequestId) = snapshot.latestEvent,
               coalescedRequestId == requestId
            {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for coalesced permission query", file: file, line: line)
    }

    private func waitForQueueCount(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            let snapshot = await coordinator.stateSnapshot()
            if snapshot.queueCountByPageId[pageId] == count {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for permission queue count", file: file, line: line)
    }
}
