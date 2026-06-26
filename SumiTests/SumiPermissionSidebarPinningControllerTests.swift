import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionSidebarPinningControllerTests: XCTestCase {
    func testReconcileFinishesPinnedSessionWhenActiveQueryLosesWindowMapping() {
        let controller = SumiPermissionSidebarPinningController()
        let windowState = BrowserWindowState()
        let query = Self.permissionQuery()

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in windowState },
            reason: "test"
        )

        XCTAssertTrue(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in nil },
            reason: "test"
        )

        XCTAssertFalse(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))
    }

    func testReconcileMovesPinnedSessionWhenActiveQueryWindowChanges() {
        let controller = SumiPermissionSidebarPinningController()
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let query = Self.permissionQuery()

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in firstWindow },
            reason: "test"
        )

        XCTAssertTrue(firstWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: firstWindow.id))
        XCTAssertFalse(secondWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: secondWindow.id))

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in secondWindow },
            reason: "test"
        )

        XCTAssertFalse(firstWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: firstWindow.id))
        XCTAssertTrue(secondWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: secondWindow.id))

        controller.reconcile(
            activeQueries: [],
            windowForPageId: { _ in secondWindow },
            reason: "test"
        )

        XCTAssertFalse(secondWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: secondWindow.id))
    }

    func testReconcileIsIdempotentForSameQueryAndWindow() {
        let controller = SumiPermissionSidebarPinningController()
        let windowState = BrowserWindowState()
        let query = Self.permissionQuery()

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in windowState },
            reason: "test"
        )
        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in windowState },
            reason: "test"
        )

        XCTAssertTrue(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))

        controller.reconcile(
            activeQueries: [],
            windowForPageId: { _ in windowState },
            reason: "test"
        )

        XCTAssertFalse(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))
    }

    func testReconcileDoesNotPinUnpromptableQueries() {
        let controller = SumiPermissionSidebarPinningController()
        let windowState = BrowserWindowState()
        let query = Self.permissionQuery(permissionTypes: [.filePicker])
        var didRequestWindow = false

        controller.reconcile(
            activeQueries: [query],
            windowForPageId: { _ in
                didRequestWindow = true
                return windowState
            },
            reason: "test"
        )

        XCTAssertFalse(didRequestWindow)
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
