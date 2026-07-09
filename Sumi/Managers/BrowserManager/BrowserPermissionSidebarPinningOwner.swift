import Foundation
import SumiDomain

final class BrowserPermissionSidebarPinningOwner {
    private let permissionStateSnapshot: @MainActor () async -> SumiPermissionCoordinatorState
    private let windowForPermissionPageId: @MainActor (String) -> BrowserWindowState?
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let pinningController: SumiPermissionSidebarPinningController

    init(
        permissionStateSnapshot: @escaping @MainActor () async -> SumiPermissionCoordinatorState,
        windowForPermissionPageId: @escaping @MainActor (String) -> BrowserWindowState?,
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        pinningController: SumiPermissionSidebarPinningController
    ) {
        self.permissionStateSnapshot = permissionStateSnapshot
        self.windowForPermissionPageId = windowForPermissionPageId
        self.windowRegistry = windowRegistry
        self.pinningController = pinningController
    }

    @MainActor
    func reconcile(reason: String) async {
        let state = await permissionStateSnapshot()
        pinningController.reconcile(
            activeQueries: Array(state.activeQueriesByPageId.values),
            windowForPageId: windowForPermissionPageId,
            windowRegistry: windowRegistry(),
            reason: reason
        )
    }
}
