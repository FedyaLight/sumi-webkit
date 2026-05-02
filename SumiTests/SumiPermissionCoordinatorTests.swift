import SwiftData
import XCTest

@testable import Sumi

final class SumiPermissionCoordinatorTests: XCTestCase {
    func testQueryPermissionStateDoesNotCreateAuthorizationQuery() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let decision = await coordinator.queryPermissionState(context(.notifications, id: "state-only"))

        XCTAssertEqual(decision.outcome, .promptRequired)
        XCTAssertEqual(decision.state, .ask)
        XCTAssertNil(decision.queryId)
        let activeQuery = await coordinator.activeQuery(forPageId: "page-a")
        XCTAssertNil(activeQuery)
    }

    func testHardDenyFromResolverReturnsImmediateDeniedWithoutStoreLookup() async {
        let store = RecordingPermissionStore()
        let resolver = RecordingPolicyResolver(
            result: .hardDeny(decision: policyDecision(source: .policy, reason: "policy-denied"))
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: resolver,
            persistentStore: store,
            now: fixedNow
        )

        let decision = await coordinator.requestPermission(context(.camera))

        XCTAssertEqual(decision.outcome, .denied)
        XCTAssertEqual(decision.source, .policy)
        XCTAssertEqual(decision.reason, "policy-denied")
        let getCount = await store.getDecisionCallCount()
        XCTAssertEqual(getCount, 0)
    }

    func testSystemBlockedReturnsSnapshotAndDoesNotRequestAuthorization() async {
        let service = FakeSumiSystemPermissionService(states: [.camera: .denied])
        let resolver = DefaultSumiPermissionPolicyResolver(systemPermissionService: service)
        let coordinator = SumiPermissionCoordinator(
            policyResolver: resolver,
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let decision = await coordinator.requestPermission(context(.camera))

        XCTAssertEqual(decision.outcome, .systemBlocked)
        XCTAssertEqual(decision.systemAuthorizationSnapshot?.state, .denied)
        XCTAssertTrue(decision.shouldOfferSystemSettings)
        let requestAuthorizationCallCount = await service.requestAuthorizationCallCount()
        XCTAssertEqual(requestAuthorizationCallCount, 0)
        let state = await coordinator.stateSnapshot()
        XCTAssertEqual(state.latestSystemBlockedEvent, .systemBlocked(decision))
    }

    func testUnsupportedReturnsImmediateUnsupported() async {
        let resolver = DefaultSumiPermissionPolicyResolver(
            systemPermissionService: FakeSumiSystemPermissionService()
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: resolver,
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let decision = await coordinator.requestPermission(context(.cameraAndMicrophone))

        XCTAssertEqual(decision.outcome, .unsupported)
        XCTAssertEqual(decision.source, .unsupported)
    }

    func testResolverRunsBeforePersistentStoreLookup() async {
        let recorder = PermissionCoordinatorEventRecorder()
        let store = RecordingPermissionStore(recorder: recorder)
        let resolver = RecordingPolicyResolver(recorder: recorder)
        let coordinator = SumiPermissionCoordinator(
            policyResolver: resolver,
            persistentStore: store,
            now: fixedNow
        )

        let task = Task {
            await coordinator.requestPermission(context(.camera, id: "request-a"))
        }
        _ = await waitForActiveQuery(coordinator)
        let events = await recorder.events()
        XCTAssertEqual(events.prefix(2), ["policy:camera", "persistent.get:camera"])

        await coordinator.cancel(pageId: "page-a")
        _ = await task.value
    }

    func testOneTimeAllowInMemoryReturnsImmediateGrantedBeforePersistentLookup() async throws {
        let memoryStore = InMemoryPermissionStore()
        let persistentStore = RecordingPermissionStore()
        let requestContext = context(.filePicker, id: "request-a")
        let key = key(.filePicker, pageId: "page-a")
        try await memoryStore.setDecision(
            for: key,
            decision: decision(.allow, persistence: .oneTime)
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: persistentStore,
            now: fixedNow
        )

        let result = await coordinator.requestPermission(requestContext)

        XCTAssertEqual(result.outcome, .granted)
        XCTAssertEqual(result.persistence, .oneTime)
        let persistentGetCount = await persistentStore.getDecisionCallCount()
        XCTAssertEqual(persistentGetCount, 0)
    }

    func testSessionAllowInMemoryReturnsImmediateGranted() async throws {
        let memoryStore = InMemoryPermissionStore()
        let permissionKey = key(.camera)
        try await memoryStore.setDecision(
            for: permissionKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: RecordingPermissionStore(),
            sessionOwnerId: "window-a",
            now: fixedNow
        )

        let result = await coordinator.requestPermission(context(.camera))

        XCTAssertEqual(result.outcome, .granted)
        XCTAssertEqual(result.persistence, .session)
    }

    func testPersistentAllowAndDenyReturnImmediateDecisionsAndRecordLastUsed() async throws {
        let store = RecordingPermissionStore()
        let cameraKey = key(.camera)
        let microphoneKey = key(.microphone)
        await store.seed(cameraKey, decision: decision(.allow, persistence: .persistent))
        await store.seed(microphoneKey, decision: decision(.deny, persistence: .persistent))
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            now: fixedNow
        )

        let allow = await coordinator.requestPermission(context(.camera))
        let deny = await coordinator.requestPermission(context(.microphone))

        XCTAssertEqual(allow.outcome, .granted)
        XCTAssertEqual(allow.persistence, .persistent)
        XCTAssertEqual(deny.outcome, .denied)
        XCTAssertEqual(deny.persistence, .persistent)
        let lastUsedCount = await store.recordLastUsedCallCount()
        XCTAssertEqual(lastUsedCount, 2)
    }

    func testPersistentAskAndMissingDecisionCreatePendingQueries() async {
        let store = RecordingPermissionStore()
        await store.seed(key(.notifications), decision: decision(.ask, persistence: .persistent))
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            now: fixedNow
        )

        let askTask = Task { await coordinator.requestPermission(context(.notifications, id: "ask")) }
        let askQuery = await waitForActiveQuery(coordinator)
        XCTAssertEqual(askQuery.permissionTypes, [.notifications])
        await coordinator.cancel(queryId: askQuery.id)
        let askResult = await askTask.value
        XCTAssertEqual(askResult.outcome, .cancelled)

        let missingTask = Task { await coordinator.requestPermission(context(.geolocation, id: "missing")) }
        let missingQuery = await waitForActiveQuery(coordinator)
        XCTAssertEqual(missingQuery.permissionTypes, [.geolocation])
        await coordinator.cancel(queryId: missingQuery.id)
        let missingResult = await missingTask.value
        XCTAssertEqual(missingResult.outcome, .cancelled)
    }

    func testDismissCooldownSuppressesPromptWithoutPersistentDeny() async {
        var currentNow = fixedNow()
        let store = RecordingPermissionStore()
        let antiAbuseStore = SumiPermissionAntiAbuseStore.memoryOnly()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            antiAbuseStore: antiAbuseStore,
            now: { currentNow }
        )

        let firstTask = Task {
            await coordinator.requestPermission(context(.notifications, id: "first"))
        }
        let query = await waitForActiveQuery(coordinator)
        await coordinator.recordPromptShown(queryId: query.id)
        await coordinator.dismiss(query.id)
        _ = await firstTask.value

        currentNow = fixedNow().addingTimeInterval(60)
        let suppressed = await coordinator.requestPermission(
            context(.notifications, id: "second")
        )

        XCTAssertEqual(suppressed.outcome, .suppressed)
        XCTAssertEqual(suppressed.source, .cooldown)
        XCTAssertEqual(suppressed.promptSuppression?.trigger, .dismissal)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
        let activeQuery = await coordinator.activeQuery(forPageId: "page-a")
        XCTAssertNil(activeQuery)
    }

    func testStoredAllowAndDenyBypassAntiAbuseSuppression() async {
        let store = RecordingPermissionStore()
        let antiAbuseStore = SumiPermissionAntiAbuseStore.memoryOnly()
        let cameraKey = key(.camera)
        let microphoneKey = key(.microphone)
        await store.seed(cameraKey, decision: decision(.allow, persistence: .persistent))
        await store.seed(microphoneKey, decision: decision(.deny, persistence: .persistent))
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                type: .userDismissed,
                key: cameraKey,
                createdAt: fixedNow()
            )
        )
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(
                type: .userDismissed,
                key: microphoneKey,
                createdAt: fixedNow()
            )
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            antiAbuseStore: antiAbuseStore,
            now: fixedNow
        )

        let allow = await coordinator.requestPermission(context(.camera))
        let deny = await coordinator.requestPermission(context(.microphone))

        XCTAssertEqual(allow.outcome, .granted)
        XCTAssertEqual(deny.outcome, .denied)
    }

    func testEphemeralProfileDoesNotOfferPersistentAndApprovePersistentDowngrades() async throws {
        let store = RecordingPermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            now: fixedNow
        )

        let task = Task {
            await coordinator.requestPermission(
                context(.camera, id: "ephemeral", isEphemeralProfile: true)
            )
        }
        let query = await waitForActiveQuery(coordinator)

        XCTAssertEqual(query.availablePersistences, [.oneTime, .session])
        XCTAssertTrue(query.disablesPersistentAllow)

        let settlement = await coordinator.approvePersistently(query.id)
        let result = await task.value

        XCTAssertEqual(settlement.persistence, .session)
        XCTAssertEqual(result.outcome, .granted)
        XCTAssertEqual(result.persistence, .session)
        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testEphemeralOneTimeAndSessionDecisionsWorkInMemory() async throws {
        let memoryStore = InMemoryPermissionStore()
        let oneTimeKey = key(.camera, pageId: "page-a", isEphemeral: true)
        let sessionKey = key(.microphone, isEphemeral: true)
        try await memoryStore.setDecision(
            for: oneTimeKey,
            decision: decision(.allow, persistence: .oneTime)
        )
        try await memoryStore.setDecision(
            for: sessionKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: RecordingPermissionStore(),
            sessionOwnerId: "window-a",
            now: fixedNow
        )

        let oneTime = await coordinator.requestPermission(
            context(.camera, isEphemeralProfile: true)
        )
        let session = await coordinator.requestPermission(
            context(.microphone, isEphemeralProfile: true)
        )

        XCTAssertEqual(oneTime.outcome, .granted)
        XCTAssertEqual(oneTime.persistence, .oneTime)
        XCTAssertEqual(session.outcome, .granted)
        XCTAssertEqual(session.persistence, .session)
    }

    func testPendingQueryIncludesSecurityAndPersistenceMetadata() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let task = Task { await coordinator.requestPermission(context(.camera, id: "metadata")) }
        let query = await waitForActiveQuery(coordinator)

        XCTAssertEqual(query.pageId, "page-a")
        XCTAssertEqual(query.profilePartitionId, "profile-a")
        XCTAssertEqual(query.displayDomain, "example.com")
        XCTAssertEqual(query.requestingOrigin, SumiPermissionOrigin(string: "https://example.com"))
        XCTAssertEqual(query.topOrigin, SumiPermissionOrigin(string: "https://example.com"))
        XCTAssertEqual(query.permissionTypes, [.camera])
        XCTAssertEqual(query.availablePersistences, [.oneTime, .session, .persistent])
        XCTAssertEqual(query.createdAt, fixedNow())

        await coordinator.cancel(queryId: query.id)
        _ = await task.value
    }

    func testFilePickerQueryOnlyAllowsOneTimePersistence() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let task = Task {
            await coordinator.requestPermission(context(.filePicker, id: "file-picker"))
        }
        let query = await waitForActiveQuery(coordinator)

        XCTAssertEqual(query.availablePersistences, [.oneTime])

        await coordinator.cancel(queryId: query.id)
        _ = await task.value
    }

    func testCameraAndMicrophoneRequestGroupsUIAndPersistsIndependently() async throws {
        let store = RecordingPermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            now: fixedNow
        )

        let task = Task {
            await coordinator.requestPermission(
                context(permissionTypes: [.camera, .microphone], id: "combined")
            )
        }
        let query = await waitForActiveQuery(coordinator)
        XCTAssertEqual(query.presentationPermissionType, .cameraAndMicrophone)

        await coordinator.approvePersistently(query.id)
        let result = await task.value

        XCTAssertEqual(result.outcome, .granted)
        XCTAssertEqual(result.persistence, .persistent)
        let storedStates = await store.storedStatesByPermission()
        XCTAssertEqual(storedStates, [
            "camera": .allow,
            "microphone": .allow,
        ])
    }

    func testNotDeterminedSystemPermissionCreatesQueryWithSystemMetadata() async {
        let resolver = DefaultSumiPermissionPolicyResolver(
            systemPermissionService: FakeSumiSystemPermissionService(states: [.camera: .notDetermined])
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: resolver,
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let task = Task { await coordinator.requestPermission(context(.camera, id: "system")) }
        let query = await waitForActiveQuery(coordinator)

        XCTAssertEqual(query.systemAuthorizationSnapshots.first?.state, .notDetermined)

        await coordinator.cancel(queryId: query.id)
        _ = await task.value
    }

    func testQueueAllowsOneActivePerPageAndPromotesFIFO() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let first = Task { await coordinator.requestPermission(context(.camera, id: "one")) }
        _ = await waitForActiveQuery(coordinator)
        let second = Task { await coordinator.requestPermission(context(.microphone, id: "two")) }
        let queueCount = await waitForQueueCount(coordinator, count: 1)
        XCTAssertEqual(queueCount, 1)

        let firstQuery = await waitForActiveQuery(coordinator)
        await coordinator.approveOnce(firstQuery.id)
        let firstResult = await first.value
        XCTAssertEqual(firstResult.outcome, .granted)

        let promoted = await waitForActiveQuery(coordinator)
        XCTAssertEqual(promoted.permissionTypes, [.microphone])
        await coordinator.approveOnce(promoted.id)
        let secondResult = await second.value
        XCTAssertEqual(secondResult.outcome, .granted)
    }

    func testCancellingActiveQueryPromotesNextQueuedQuery() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let first = Task { await coordinator.requestPermission(context(.camera, id: "one")) }
        _ = await waitForActiveQuery(coordinator)
        let second = Task { await coordinator.requestPermission(context(.microphone, id: "two")) }
        _ = await waitForQueueCount(coordinator, count: 1)

        let firstQuery = await waitForActiveQuery(coordinator)
        await coordinator.cancel(queryId: firstQuery.id)
        let firstResult = await first.value
        XCTAssertEqual(firstResult.outcome, .cancelled)

        let promoted = await waitForActiveQuery(coordinator)
        XCTAssertEqual(promoted.permissionTypes, [.microphone])
        await coordinator.approveOnce(promoted.id)
        let secondResult = await second.value
        XCTAssertEqual(secondResult.outcome, .granted)
    }

    func testDuplicatePendingRequestCoalescesAndResolvesAllWaiters() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let first = Task { await coordinator.requestPermission(context(.camera, id: "one")) }
        let query = await waitForActiveQuery(coordinator)
        let second = Task { await coordinator.requestPermission(context(.camera, id: "two")) }
        await waitForCoalescedRequest(coordinator, requestId: "two")
        let state = await coordinator.stateSnapshot()
        XCTAssertEqual(state.activeQueriesByPageId["page-a"]?.id, query.id)
        XCTAssertEqual(state.queueCountByPageId["page-a"] ?? 0, 0)

        await coordinator.approveOnce(query.id)

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult.outcome, .granted)
        XCTAssertEqual(secondResult.outcome, .granted)
        XCTAssertEqual(firstResult.queryId, secondResult.queryId)
    }

    func testCancellationByPageAndNavigationResolvePendingRequests() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let first = Task { await coordinator.requestPermission(context(.camera, id: "one")) }
        _ = await waitForActiveQuery(coordinator)
        let second = Task { await coordinator.requestPermission(context(.microphone, id: "two")) }
        _ = await waitForQueueCount(coordinator, count: 1)

        await coordinator.cancel(pageId: "page-a")

        let firstResult = await first.value
        let secondResult = await second.value
        let activeQuery = await coordinator.activeQuery(forPageId: "page-a")
        XCTAssertEqual(firstResult.outcome, .cancelled)
        XCTAssertEqual(secondResult.outcome, .cancelled)
        XCTAssertNil(activeQuery)

        let navigationTask = Task {
            await coordinator.requestPermission(context(.geolocation, id: "navigation"))
        }
        _ = await waitForActiveQuery(coordinator)
        await coordinator.cancelNavigation(pageId: "page-a")
        let navigationResult = await navigationTask.value
        XCTAssertEqual(navigationResult.outcome, .cancelled)
    }

    func testProfileAndSessionCancellationResolvePendingAndClearSessionMemory() async throws {
        let memoryStore = InMemoryPermissionStore()
        try await memoryStore.setDecision(
            for: key(.camera),
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: RecordingPermissionStore(),
            sessionOwnerId: "window-a",
            now: fixedNow
        )

        let sessionTask = Task {
            await coordinator.requestPermission(context(.microphone, id: "session"))
        }
        _ = await waitForActiveQuery(coordinator)
        await coordinator.cancelSession(ownerId: "window-a")
        let sessionResult = await sessionTask.value
        let clearedSessionRecord = try await memoryStore.getDecision(
            for: key(.camera),
            sessionOwnerId: "window-a"
        )
        XCTAssertEqual(sessionResult.outcome, .cancelled)
        XCTAssertNil(clearedSessionRecord)

        let profileTask = Task {
            await coordinator.requestPermission(context(.geolocation, id: "profile"))
        }
        _ = await waitForActiveQuery(coordinator)
        await coordinator.cancelProfile(profilePartitionId: "profile-a")
        let profileResult = await profileTask.value
        XCTAssertEqual(profileResult.outcome, .cancelled)
    }

    func testSettlementWritesExpectedStores() async throws {
        let memoryStore = InMemoryPermissionStore()
        let persistentStore = RecordingPermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            memoryStore: memoryStore,
            persistentStore: persistentStore,
            sessionOwnerId: "window-a",
            now: fixedNow
        )

        let once = Task { await coordinator.requestPermission(context(.camera, id: "once")) }
        let onceQuery = await waitForActiveQuery(coordinator)
        await coordinator.approveOnce(onceQuery.id)
        let onceResult = await once.value
        let onceRecord = try await memoryStore.getDecision(for: key(.camera, pageId: "page-a"))
        XCTAssertEqual(onceResult.outcome, .granted)
        XCTAssertEqual(onceRecord?.decision.persistence, .oneTime)

        let session = Task { await coordinator.requestPermission(context(.microphone, id: "session")) }
        let sessionQuery = await waitForActiveQuery(coordinator)
        await coordinator.approveForSession(sessionQuery.id)
        let sessionSettlementResult = await session.value
        let sessionRecord = try await memoryStore.getDecision(
            for: key(.microphone),
            sessionOwnerId: "window-a"
        )
        XCTAssertEqual(sessionSettlementResult.persistence, .session)
        XCTAssertEqual(sessionRecord?.decision.persistence, .session)

        let persistent = Task { await coordinator.requestPermission(context(.geolocation, id: "persistent")) }
        let persistentQuery = await waitForActiveQuery(coordinator)
        await coordinator.approvePersistently(persistentQuery.id)
        let persistentResult = await persistent.value
        let geolocationState = await persistentStore.state(for: key(.geolocation))
        XCTAssertEqual(persistentResult.persistence, .persistent)
        XCTAssertEqual(geolocationState, .allow)

        let denied = Task { await coordinator.requestPermission(context(.notifications, id: "deny")) }
        let deniedQuery = await waitForActiveQuery(coordinator)
        await coordinator.denyPersistently(deniedQuery.id)
        let deniedResult = await denied.value
        let notificationsState = await persistentStore.state(for: key(.notifications))
        XCTAssertEqual(deniedResult.outcome, .denied)
        XCTAssertEqual(notificationsState, .deny)

    }

    func testDismissAndCancelDoNotWritePersistentStore() async {
        let store = RecordingPermissionStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: store,
            now: fixedNow
        )

        let dismissTask = Task { await coordinator.requestPermission(context(.camera, id: "dismiss")) }
        let dismissQuery = await waitForActiveQuery(coordinator)
        await coordinator.dismiss(dismissQuery.id)
        let dismissResult = await dismissTask.value
        XCTAssertEqual(dismissResult.outcome, .dismissed)

        let cancelTask = Task { await coordinator.requestPermission(context(.microphone, id: "cancel")) }
        let cancelQuery = await waitForActiveQuery(coordinator)
        await coordinator.cancel(queryId: cancelQuery.id)
        let cancelResult = await cancelTask.value
        XCTAssertEqual(cancelResult.outcome, .cancelled)

        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testCancellingOneCoalescedRequestDoesNotDoubleResolveRemainingWaiter() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: RecordingPolicyResolver(),
            persistentStore: RecordingPermissionStore(),
            now: fixedNow
        )

        let first = Task { await coordinator.requestPermission(context(.camera, id: "one")) }
        let query = await waitForActiveQuery(coordinator)
        let second = Task { await coordinator.requestPermission(context(.camera, id: "two")) }
        await waitForCoalescedRequest(coordinator, requestId: "two")

        await coordinator.cancel(requestId: "two")
        let secondResult = await second.value
        XCTAssertEqual(secondResult.outcome, .cancelled)

        await coordinator.approveOnce(query.id)
        let firstResult = await first.value
        XCTAssertEqual(firstResult.outcome, .granted)
    }

    private func waitForActiveQuery(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String = "page-a",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SumiPermissionAuthorizationQuery {
        for _ in 0..<100 {
            if let query = await coordinator.activeQuery(forPageId: pageId) {
                return query
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for active permission query", file: file, line: line)
        return SumiPermissionAuthorizationQuery(
            id: "missing",
            pageId: pageId,
            profilePartitionId: "profile-a",
            displayDomain: "missing",
            requestingOrigin: SumiPermissionOrigin.invalid(),
            topOrigin: SumiPermissionOrigin.invalid(),
            permissionTypes: [],
            presentationPermissionType: nil,
            availablePersistences: [],
            systemAuthorizationSnapshots: [],
            policyReasons: [],
            createdAt: fixedNow(),
            isEphemeralProfile: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: false,
        )
    }

    private func waitForQueueCount(
        _ coordinator: SumiPermissionCoordinator,
        pageId: String = "page-a",
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Int {
        for _ in 0..<100 {
            let state = await coordinator.stateSnapshot()
            let currentCount = state.queueCountByPageId[pageId] ?? 0
            if currentCount == count {
                return currentCount
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for permission queue count \(count)", file: file, line: line)
        return -1
    }

    private func waitForCoalescedRequest(
        _ coordinator: SumiPermissionCoordinator,
        requestId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            let state = await coordinator.stateSnapshot()
            if case .queryCoalesced(_, let coalescedRequestId) = state.latestEvent,
               coalescedRequestId == requestId
            {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for coalesced permission request", file: file, line: line)
    }

    private func context(
        _ type: SumiPermissionType,
        id: String = "request-a",
        pageId: String = "page-a",
        profile: String = "profile-a",
        isEphemeralProfile: Bool = false,
        hasUserGesture: Bool = true
    ) -> SumiPermissionSecurityContext {
        context(
            permissionTypes: [type],
            id: id,
            pageId: pageId,
            profile: profile,
            isEphemeralProfile: isEphemeralProfile,
            hasUserGesture: hasUserGesture
        )
    }

    private func context(
        permissionTypes: [SumiPermissionType],
        id: String = "request-a",
        pageId: String = "page-a",
        profile: String = "profile-a",
        isEphemeralProfile: Bool = false,
        hasUserGesture: Bool = true
    ) -> SumiPermissionSecurityContext {
        let request = SumiPermissionRequest(
            id: id,
            tabId: "tab-a",
            pageId: pageId,
            frameId: "frame-a",
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: permissionTypes,
            requestedAt: fixedNow(),
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profile
        )
        return SumiPermissionSecurityContext(
            request: request,
            committedURL: URL(string: "https://example.com"),
            visibleURL: URL(string: "https://example.com"),
            mainFrameURL: URL(string: "https://example.com"),
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profile,
            transientPageId: pageId,
            now: fixedNow()
        )
    }
}

private actor PermissionCoordinatorEventRecorder {
    private var recordedEvents: [String] = []

    func append(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }
}

private actor RecordingPolicyResolver: SumiPermissionPolicyResolver {
    private let result: SumiPermissionPolicyResult?
    private let recorder: PermissionCoordinatorEventRecorder?
    private var callCount = 0

    init(
        result: SumiPermissionPolicyResult? = nil,
        recorder: PermissionCoordinatorEventRecorder? = nil
    ) {
        self.result = result
        self.recorder = recorder
    }

    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        callCount += 1
        let permissionType = context.request.permissionTypes.first ?? .storageAccess
        await recorder?.append("policy:\(permissionType.identity)")
        if let result {
            return result
        }
        return .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
            allowedPersistences: allowedPersistences(
                permissionType: permissionType,
                isEphemeralProfile: context.isEphemeralProfile
            )
        )
    }

    func evaluationCallCount() -> Int {
        callCount
    }

    private func allowedPersistences(
        permissionType: SumiPermissionType,
        isEphemeralProfile: Bool
    ) -> Set<SumiPermissionPersistence> {
        if permissionType.isOneTimeOnly {
            return [.oneTime]
        }
        if isEphemeralProfile {
            return [.oneTime, .session]
        }
        return [.oneTime, .session, .persistent]
    }
}

private actor RecordingPermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private let recorder: PermissionCoordinatorEventRecorder?
    private var getCount = 0
    private var setCount = 0
    private var lastUsedCount = 0

    init(recorder: PermissionCoordinatorEventRecorder? = nil) {
        self.recorder = recorder
    }

    func seed(_ key: SumiPermissionKey, decision: SumiPermissionDecision) {
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        getCount += 1
        await recorder?.append("persistent.get:\(key.permissionType.identity)")
        return records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        setCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values.filter { $0.key.profilePartitionId == profileId }
    }

    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let domain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        return try await listDecisions(profilePartitionId: profilePartitionId)
            .filter { $0.displayDomain == domain }
    }

    func clearAll(profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in record.key.profilePartitionId != profileId }
    }

    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId: String
    ) async throws {
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in !domains.contains(record.displayDomain) }
    }

    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId: String
    ) async throws {
        let originIdentities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            !originIdentities.contains(record.key.requestingOrigin.identity)
                && !originIdentities.contains(record.key.topOrigin.identity)
        }
    }

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int {
        0
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        lastUsedCount += 1
        guard let record = records[key.persistentIdentity] else { return }
        records[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: record.key,
            decision: record.decision.recordingLastUsed(at: date),
            displayDomain: record.displayDomain
        )
    }

    func getDecisionCallCount() -> Int {
        getCount
    }

    func setDecisionCallCount() -> Int {
        setCount
    }

    func recordLastUsedCallCount() -> Int {
        lastUsedCount
    }

    func state(for key: SumiPermissionKey) -> SumiPermissionState? {
        records[key.persistentIdentity]?.decision.state
    }

    func storedStatesByPermission() -> [String: SumiPermissionState] {
        Dictionary(
            uniqueKeysWithValues: records.values.map {
                ($0.key.permissionType.identity, $0.decision.state)
            }
        )
    }
}

private func key(
    _ type: SumiPermissionType,
    pageId: String? = nil,
    profile: String = "profile-a",
    isEphemeral: Bool = false
) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionType: type,
        profilePartitionId: profile,
        transientPageId: pageId,
        isEphemeralProfile: isEphemeral
    )
}

private func decision(
    _ state: SumiPermissionState,
    persistence: SumiPermissionPersistence
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: state,
        persistence: persistence,
        source: .user,
        reason: "test",
        createdAt: fixedNow(),
        updatedAt: fixedNow()
    )
}

private func policyDecision(
    source: SumiPermissionDecisionSource,
    reason: String
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: .deny,
        persistence: .session,
        source: source,
        reason: reason,
        createdAt: fixedNow(),
        updatedAt: fixedNow()
    )
}

private func fixedNow() -> Date {
    ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!
}
