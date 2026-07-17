import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionEventOwnerTests: XCTestCase {
    func testRecordsPermissionEventsAndCancelsSingleSubscription() async {
        let coordinator = PermissionEventOwnerFakeCoordinator()
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = SumiPermissionSiteActivityStore()
        var handledEvents: [SumiPermissionCoordinatorEvent] = []
        let handledExpectation = expectation(description: "permission event handled")
        let owner = SumiPermissionEventOwner(
            coordinator: coordinator,
            recentActivityStore: recentActivityStore,
            siteActivityStore: siteActivityStore,
            onEvent: { event in
                handledEvents.append(event)
                handledExpectation.fulfill()
            }
        )

        let subscriptionEvent = await coordinator.nextLifecycleEvent()
        XCTAssertEqual(subscriptionEvent, .subscribed)
        let subscriptionCount = await coordinator.subscriptionCount
        XCTAssertEqual(subscriptionCount, 1)

        let query = Self.permissionQuery()
        await coordinator.emit(.queryActivated(query))

        await fulfillment(of: [handledExpectation], timeout: 1)
        XCTAssertEqual(handledEvents, [.queryActivated(query)])
        XCTAssertEqual(recentActivityStore.records.first?.permissionType, .camera)
        XCTAssertEqual(recentActivityStore.records.first?.action, .asked)

        let siteRecords = siteActivityStore.records(
            forSiteOf: query.topOrigin,
            profilePartitionId: query.profilePartitionId,
            isEphemeralProfile: query.isEphemeralProfile
        )
        XCTAssertEqual(siteRecords.count, 1)
        XCTAssertEqual(siteRecords.first?.permissionType, .camera)
        XCTAssertEqual(siteRecords.first?.hasRequested, true)

        owner.cancel()
        let terminationEvent = await coordinator.nextLifecycleEvent()
        let terminationCount = await coordinator.terminationCount
        XCTAssertEqual(terminationEvent, .terminated)
        XCTAssertEqual(terminationCount, 1)
    }

    private static func permissionQuery() -> SumiPermissionAuthorizationQuery {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionAuthorizationQuery(
            id: "permission-query-a",
            pageId: "tab-a:1",
            profilePartitionId: "profile-a",
            displayDomain: "example.com",
            requestingOrigin: origin,
            topOrigin: origin,
            permissionTypes: [.camera],
            presentationPermissionType: nil,
            availablePersistences: [.persistent],
            systemAuthorizationSnapshots: [],
            policyReasons: [],
            createdAt: Date(timeIntervalSince1970: 100),
            isEphemeralProfile: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: false
        )
    }
}

private actor PermissionEventOwnerFakeCoordinator: SumiPermissionCoordinating {
    enum LifecycleEvent: Equatable {
        case subscribed
        case terminated
    }

    private var continuations: [AsyncStream<SumiPermissionCoordinatorEvent>.Continuation] = []
    private let lifecycleEvents: AsyncStream<LifecycleEvent>
    private let lifecycleEventContinuation: AsyncStream<LifecycleEvent>.Continuation
    private(set) var subscriptionCount = 0
    private(set) var terminationCount = 0

    init() {
        let events = AsyncStream<LifecycleEvent>.makeStream(bufferingPolicy: .unbounded)
        lifecycleEvents = events.stream
        lifecycleEventContinuation = events.continuation
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .defaultSetting,
            reason: "fake",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery? {
        _ = pageId
        return nil
    }

    func stateSnapshot() async -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        subscriptionCount += 1
        lifecycleEventContinuation.yield(.subscribed)
        let pair = AsyncStream<SumiPermissionCoordinatorEvent>.makeStream(
            of: SumiPermissionCoordinatorEvent.self,
            bufferingPolicy: .bufferingNewest(50)
        )
        continuations.append(pair.continuation)
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.recordTermination()
            }
        }
        return pair.stream
    }

    func emit(_ event: SumiPermissionCoordinatorEvent) {
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    private func recordTermination() {
        terminationCount += 1
        lifecycleEventContinuation.yield(.terminated)
    }

    func nextLifecycleEvent() async -> LifecycleEvent? {
        for await event in lifecycleEvents {
            return event
        }
        return nil
    }
}
