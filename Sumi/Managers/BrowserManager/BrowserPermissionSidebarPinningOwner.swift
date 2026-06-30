import Foundation

final class BrowserPermissionSidebarPinningOwner {
    struct Dependencies {
        let permissionStateSnapshot: @MainActor () async -> SumiPermissionCoordinatorState
        let windowForPermissionPageId: @MainActor (String) -> BrowserWindowState?
    }

    private let dependencies: Dependencies
    private let pinningController: SumiPermissionSidebarPinningController

    init(
        dependencies: Dependencies,
        pinningController: SumiPermissionSidebarPinningController
    ) {
        self.dependencies = dependencies
        self.pinningController = pinningController
    }

    @MainActor
    func reconcile(reason: String) async {
        let state = await dependencies.permissionStateSnapshot()
        pinningController.reconcile(
            activeQueries: Array(state.activeQueriesByPageId.values),
            windowForPageId: dependencies.windowForPermissionPageId,
            reason: reason
        )
    }
}
