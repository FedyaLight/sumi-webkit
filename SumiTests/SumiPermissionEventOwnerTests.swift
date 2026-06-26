import Foundation
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionEventOwnerTests: XCTestCase {
    func testRecordsPermissionEventsAndCancelsSingleSubscription() async {
        let coordinator = PermissionEventOwnerFakeCoordinator()
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = SumiPermissionSiteActivityStore(
            userDefaults: UserDefaults(suiteName: "SumiPermissionEventOwner-\(UUID().uuidString)")!
        )
        var handledEvents: [SumiPermissionCoordinatorEvent] = []
        let owner = SumiPermissionEventOwner(
            coordinator: coordinator,
            recentActivityStore: recentActivityStore,
            siteActivityStore: siteActivityStore,
            onEvent: { event in
                handledEvents.append(event)
            }
        )

        await waitUntil {
            await coordinator.subscriptionCount == 1
        }
        XCTAssertEqual(await coordinator.subscriptionCount, 1)

        let query = Self.permissionQuery()
        await coordinator.emit(.queryActivated(query))

        await waitUntil {
            handledEvents.count == 1 && recentActivityStore.records.count == 1
        }
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
        await waitUntil {
            await coordinator.terminationCount == 1
        }
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

    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

private actor PermissionEventOwnerFakeCoordinator: SumiPermissionCoordinating {
    private var continuations: [AsyncStream<SumiPermissionCoordinatorEvent>.Continuation] = []
    private(set) var subscriptionCount = 0
    private(set) var terminationCount = 0

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
    }
}
