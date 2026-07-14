import XCTest

@testable import Sumi
import SumiDomain

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
        var events = await coordinator.events().makeAsyncIterator()
        let primaryContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-primary")
        let primaryTask = Task {
            await coordinator.requestPermission(primaryContext)
        }
        let primaryQuery = await waitForActiveQuery(from: &events)

        let coalescedContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-coalesced")
        let coalescedTask = Task {
            await coordinator.requestPermission(coalescedContext)
        }
        await waitForCoalescedRequest(
            from: &events,
            requestId: "camera-coalesced"
        )

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
        var events = await coordinator.events().makeAsyncIterator()
        let firstContext = pendingQueryContext(permissionTypes: [.camera], id: "camera-primary")
        let firstTask = Task {
            await coordinator.requestPermission(firstContext)
        }
        let firstQuery = await waitForActiveQuery(from: &events)

        let secondContext = pendingQueryContext(permissionTypes: [.microphone], id: "microphone-queued")
        let secondTask = Task {
            await coordinator.requestPermission(secondContext)
        }
        await waitForQueuedQuery(from: &events, pageId: "tab-a:1")
        let queuedSnapshot = await coordinator.stateSnapshot()
        XCTAssertEqual(queuedSnapshot.queueCountByPageId["tab-a:1"], 1)

        await coordinator.approveOnce(firstQuery.id)
        let firstDecision = await firstTask.value
        XCTAssertEqual(firstDecision.outcome, .granted)

        let promotedQuery = await waitForActiveQuery(from: &events) { query in
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
        from events: inout AsyncStream<SumiPermissionCoordinatorEvent>.Iterator,
        where isMatch: (SumiPermissionAuthorizationQuery) -> Bool = { _ in true },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SumiPermissionAuthorizationQuery {
        while let event = await events.next() {
            let query: SumiPermissionAuthorizationQuery
            switch event {
            case .queryActivated(let activated), .queryPromoted(let activated):
                query = activated
            default:
                continue
            }
            if isMatch(query) {
                return query
            }
        }
        XCTFail("Permission event stream ended before an active query", file: file, line: line)
        fatalError("Permission event stream ended before an active query")
    }

    private func waitForCoalescedRequest(
        from events: inout AsyncStream<SumiPermissionCoordinatorEvent>.Iterator,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        while let event = await events.next() {
            if case .queryCoalesced(_, let coalescedRequestId) = event,
               coalescedRequestId == requestId {
                return
            }
        }
        XCTFail("Permission event stream ended before query coalescing", file: file, line: line)
    }

    private func waitForQueuedQuery(
        from events: inout AsyncStream<SumiPermissionCoordinatorEvent>.Iterator,
        pageId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        while let event = await events.next() {
            if case .queryQueued(let query, _) = event,
               query.pageId == pageId {
                return
            }
        }
        XCTFail("Permission event stream ended before query queuing", file: file, line: line)
    }
}
