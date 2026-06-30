import XCTest

@testable import Sumi

@MainActor
final class BrowserPermissionSidebarPinningOwnerTests: XCTestCase {
    func testReconcilePinsFromPermissionSnapshotAndWindowResolver() async {
        let windowState = BrowserWindowState()
        let query = Self.permissionQuery()
        var snapshot = SumiPermissionCoordinatorState(
            activeQueriesByPageId: [query.pageId: query]
        )
        var requestedPageIds: [String] = []
        let owner = BrowserPermissionSidebarPinningOwner(
            dependencies: BrowserPermissionSidebarPinningOwner.Dependencies(
                permissionStateSnapshot: {
                    snapshot
                },
                windowForPermissionPageId: { pageId in
                    requestedPageIds.append(pageId)
                    return pageId == query.pageId ? windowState : nil
                }
            ),
            pinningController: SumiPermissionSidebarPinningController()
        )

        await owner.reconcile(reason: "test")

        XCTAssertEqual(requestedPageIds, [query.pageId])
        XCTAssertTrue(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))

        snapshot = SumiPermissionCoordinatorState(
            activeQueriesByPageId: [:],
            queueCountByPageId: [:],
            latestEvent: nil,
            latestSystemBlockedEvent: nil
        )
        await owner.reconcile(reason: "test")

        XCTAssertFalse(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))
    }

    private static func permissionQuery(
        id: String = "permission-query-a",
        pageId: String = "tab-a:1",
        permissionTypes: [SumiPermissionType] = [.camera]
    ) -> SumiPermissionAuthorizationQuery {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        return SumiPermissionAuthorizationQuery(
            id: id,
            pageId: pageId,
            profilePartitionId: "profile-a",
            displayDomain: "example.com",
            requestingOrigin: origin,
            topOrigin: origin,
            permissionTypes: permissionTypes,
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
