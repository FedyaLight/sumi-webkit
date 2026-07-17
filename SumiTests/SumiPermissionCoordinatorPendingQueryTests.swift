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

    func testProfileRetirementCancelsActiveQueryAndRejectsLateRequests() async {
        let coordinator = makeCoordinator()
        let targetContext = sumiPermissionIntegrationContext(
            [.camera],
            id: "target-active",
            profilePartitionId: "target-profile"
        )
        let targetTask = Task {
            await coordinator.requestPermission(targetContext)
        }
        _ = await sumiPermissionIntegrationWaitForActiveQuery(coordinator)

        let retirementDecision = await coordinator.retireProfile(
            profilePartitionId: "target-profile",
            reason: "test-profile-retired"
        )

        let targetDecision = await targetTask.value
        XCTAssertEqual(retirementDecision.outcome, .cancelled)
        XCTAssertEqual(targetDecision.outcome, .cancelled)
        let targetIsRetired = await coordinator.isProfileRetired(
            "target-profile"
        )
        let activeQuery = await coordinator.activeQuery(forPageId: "tab-a:1")
        XCTAssertTrue(targetIsRetired)
        XCTAssertNil(activeQuery)

        let lateTargetDecision = await coordinator.requestPermission(
            sumiPermissionIntegrationContext(
                [.camera],
                id: "target-late",
                profilePartitionId: "target-profile"
            )
        )
        XCTAssertEqual(lateTargetDecision.outcome, .cancelled)
        XCTAssertEqual(lateTargetDecision.reason, "profile-retired")

        let retainedDecision = await coordinator.queryPermissionState(
            sumiPermissionIntegrationContext(
                [.camera],
                id: "retained-query",
                profilePartitionId: "retained-profile"
            )
        )
        XCTAssertEqual(retainedDecision.outcome, .promptRequired)
    }

    func testRetirementDrainsAdmittedWriteThenBlocksRecreation() async throws {
        let store = SuspendingPermissionRetirementStore()
        let coordinator = makeCoordinator(persistentStore: store)
        var events = await coordinator.events().makeAsyncIterator()
        let targetKey = sumiPermissionIntegrationKey(
            .camera,
            profilePartitionId: "target-profile",
            pageId: nil
        )
        let retainedKey = sumiPermissionIntegrationKey(
            .camera,
            requestingOrigin: sumiPermissionIntegrationOrigin(
                "https://retained.example"
            ),
            topOrigin: sumiPermissionIntegrationOrigin(
                "https://retained.example"
            ),
            profilePartitionId: "retained-profile",
            pageId: nil
        )

        let admittedWrite = Task {
            try await coordinator.setSiteDecision(
                for: targetKey,
                state: .allow,
                source: .user,
                reason: "admitted-before-retirement"
            )
        }
        await store.waitUntilWriteIsSuspended()
        let retirementCompletion = PermissionRetirementCompletionProbe()
        let retirement = Task {
            let decision = await coordinator.retireProfile(
                profilePartitionId: "target-profile",
                reason: "test-profile-retired"
            )
            await retirementCompletion.markCompleted()
            return decision
        }
        await waitForProfileRetirementCancellation(
            from: &events,
            profilePartitionId: "target-profile"
        )
        let retirementCompletedBeforeWriteDrain = await retirementCompletion
            .isCompleted()
        XCTAssertFalse(retirementCompletedBeforeWriteDrain)

        await store.resumeWrite()
        try await admittedWrite.value
        _ = await retirement.value

        await store.resetDecision(for: targetKey)
        do {
            try await coordinator.setSiteDecision(
                for: targetKey,
                state: .allow,
                source: .user,
                reason: "late-recreation"
            )
            XCTFail("Retired profile accepted a late persistent decision")
        } catch SumiPermissionSiteDecisionError.unavailable {
            // Expected fail-closed behavior.
        }

        try await coordinator.setSiteDecision(
            for: retainedKey,
            state: .allow,
            source: .user,
            reason: "retained-profile-write"
        )
        let targetRecords = await store.listDecisions(
            profilePartitionId: "target-profile"
        )
        let retainedRecords = await store.listDecisions(
            profilePartitionId: "retained-profile"
        )
        XCTAssertTrue(targetRecords.isEmpty)
        XCTAssertEqual(
            retainedRecords.count,
            1
        )
    }

    func testRetirementDrainsAdmittedSettlementBeforeReturning() async throws {
        let store = SuspendingPermissionRetirementStore()
        let coordinator = makeCoordinator(persistentStore: store)
        var events = await coordinator.events().makeAsyncIterator()
        let context = pendingQueryContext(
            permissionTypes: [.camera],
            id: "target-persistent-settlement"
        )
        let targetKey = sumiPermissionIntegrationKey(
            .camera,
            profilePartitionId: context.profilePartitionId,
            pageId: nil
        )
        let request = Task {
            await coordinator.requestPermission(context)
        }
        let query = await waitForActiveQuery(from: &events)
        let settlement = Task {
            await coordinator.approvePersistently(query.id)
        }
        await store.waitUntilWriteIsSuspended()

        let retirementCompletion = PermissionRetirementCompletionProbe()
        let retirement = Task {
            let decision = await coordinator.retireProfile(
                profilePartitionId: context.profilePartitionId,
                reason: "test-profile-retired"
            )
            await retirementCompletion.markCompleted()
            return decision
        }
        await waitForProfileRetirementCancellation(
            from: &events,
            profilePartitionId: context.profilePartitionId
        )

        let requestDecision = await request.value
        let completedBeforeWriteDrain = await retirementCompletion.isCompleted()
        let writesBeforeDrain = await store.setInvocationCount()
        let recordsBeforeDrain = await store.records(
            profilePartitionId: context.profilePartitionId
        )
        XCTAssertEqual(requestDecision.outcome, .cancelled)
        XCTAssertFalse(completedBeforeWriteDrain)
        XCTAssertEqual(writesBeforeDrain, 1)
        XCTAssertTrue(recordsBeforeDrain.isEmpty)

        await store.resumeWrite()
        let settlementDecision = await settlement.value
        _ = await retirement.value

        XCTAssertEqual(settlementDecision.outcome, .granted)
        let recordsAfterDrain = await store.records(
            profilePartitionId: context.profilePartitionId
        )
        XCTAssertEqual(recordsAfterDrain.count, 1)
        let snapshotAfterRetirement = await coordinator.stateSnapshot()
        guard case .querySettled(let settledQueryID, _) = snapshotAfterRetirement.latestEvent else {
            return XCTFail("Retirement returned before the admitted settlement event")
        }
        XCTAssertEqual(settledQueryID, query.id)

        do {
            try await coordinator.setSiteDecision(
                for: targetKey,
                state: .deny,
                source: .user,
                reason: "post-retirement-write"
            )
            XCTFail("Retired profile accepted a post-retirement write")
        } catch SumiPermissionSiteDecisionError.unavailable {
            // Expected fail-closed behavior.
        }
        let finalWriteCount = await store.setInvocationCount()
        let finalEvent = await coordinator.stateSnapshot().latestEvent
        XCTAssertEqual(finalWriteCount, 1)
        XCTAssertEqual(
            finalEvent,
            snapshotAfterRetirement.latestEvent
        )
    }

    private func makeCoordinator(
        persistentStore: any SumiPermissionStore = SumiPermissionIntegrationStore()
    ) -> SumiPermissionCoordinator {
        SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService(
                    states: sumiPermissionIntegrationAuthorizedSystemStates()
                )
            ),
            persistentStore: persistentStore,
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

    private func waitForProfileRetirementCancellation(
        from events: inout AsyncStream<SumiPermissionCoordinatorEvent>.Iterator,
        profilePartitionId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        while let event = await events.next() {
            if case .profileCancelled(let cancelledProfileID, _) = event,
               cancelledProfileID == profilePartitionId {
                return
            }
        }
        XCTFail(
            "Permission event stream ended before profile retirement cancellation",
            file: file,
            line: line
        )
    }
}

private actor PermissionRetirementCompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

private actor SuspendingPermissionRetirementStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var suspendedWrite: CheckedContinuation<Void, Never>?
    private var writeSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspendNextWrite = true
    private var writeCount = 0

    func getDecision(
        for key: SumiPermissionKey
    ) async -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(
        for key: SumiPermissionKey,
        decision: SumiPermissionDecision
    ) async {
        writeCount += 1
        if shouldSuspendNextWrite {
            shouldSuspendNextWrite = false
            await withCheckedContinuation { continuation in
                suspendedWrite = continuation
                let waiters = writeSuspensionWaiters
                writeSuspensionWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        records[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: key,
            decision: decision
        )
    }

    func resetDecision(for key: SumiPermissionKey) async {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(
        profilePartitionId: String
    ) async -> [SumiPermissionStoreRecord] {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        return records.values.filter {
            $0.key.profilePartitionId == profileID
        }
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async {}

    func waitUntilWriteIsSuspended() async {
        guard suspendedWrite == nil else { return }
        await withCheckedContinuation { continuation in
            writeSuspensionWaiters.append(continuation)
        }
    }

    func resumeWrite() {
        suspendedWrite?.resume()
        suspendedWrite = nil
    }

    func setInvocationCount() -> Int {
        writeCount
    }

    func records(
        profilePartitionId: String
    ) -> [SumiPermissionStoreRecord] {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        return records.values.filter {
            $0.key.profilePartitionId == profileID
        }
    }
}
