import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class PermissionSidebarPinningOwnerTests: XCTestCase {
    func testReconcilePinsFromPermissionSnapshotAndWindowResolver() async {
        let coordinator = PermissionSidebarPinningCoordinator()
        let browserManager = BrowserManager(permissionCoordinator: coordinator)
        let windowState = BrowserWindowState()
        let profile = Profile(name: "Permission")
        let space = Space(name: "Permission", profileId: profile.id)
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        browserManager.windowRegistry.register(windowState)
        browserManager.windowRegistry.setActive(windowState)
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: space,
            activate: false
        )
        windowState.currentTabId = tab.id
        let query = Self.permissionQuery(pageId: tab.currentPermissionPageId())
        await coordinator.replaceState(
            SumiPermissionCoordinatorState(
                activeQueriesByPageId: [query.pageId: query]
            )
        )
        let owner = BrowserPermissionSidebarPinningOwner(
            permissionRuntime: browserManager.permissionRuntime,
            windows: browserManager.windowRegistry,
            windowTabs: browserManager.shellRuntime.windowTabs,
            pinningController: SumiPermissionSidebarPinningController()
        )

        await owner.reconcile(reason: "test")

        XCTAssertTrue(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))

        await coordinator.replaceState(
            SumiPermissionCoordinatorState()
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

private actor PermissionSidebarPinningCoordinator: SumiPermissionCoordinating {
    private var state = SumiPermissionCoordinatorState()

    func replaceState(_ state: SumiPermissionCoordinatorState) {
        self.state = state
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .defaultSetting,
            reason: "permission-sidebar-pinning-test",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(
        forPageId pageId: String
    ) async -> SumiPermissionAuthorizationQuery? {
        state.activeQueriesByPageId[pageId]
    }

    func stateSnapshot() async -> SumiPermissionCoordinatorState {
        state
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
