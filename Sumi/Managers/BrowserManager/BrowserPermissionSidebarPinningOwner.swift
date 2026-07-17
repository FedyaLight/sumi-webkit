import Foundation
import SumiDomain

@MainActor
final class BrowserPermissionSidebarPinningOwner {
    private let permissionRuntime: BrowserManagerPermissionRuntime
    private let windows: WindowRegistry
    private let windowTabs: BrowserWindowTabContext
    private let pinningController: SumiPermissionSidebarPinningController
    private var scheduledReconciliation: Task<Void, Never>?
    private var reconciliationRevision: UInt64 = 0

    init(
        permissionRuntime: BrowserManagerPermissionRuntime,
        windows: WindowRegistry,
        windowTabs: BrowserWindowTabContext,
        pinningController: SumiPermissionSidebarPinningController
    ) {
        self.permissionRuntime = permissionRuntime
        self.windows = windows
        self.windowTabs = windowTabs
        self.pinningController = pinningController
    }

    func reconcile(reason: String) async {
        let state = await permissionRuntime.permissionCoordinator
            .stateSnapshot()
        apply(state, reason: reason)
    }

    func scheduleReconciliation(reason: String) {
        reconciliationRevision &+= 1
        let revision = reconciliationRevision
        let permissionRuntime = permissionRuntime
        scheduledReconciliation?.cancel()
        scheduledReconciliation = Task { @MainActor [weak self] in
            let state = await permissionRuntime.permissionCoordinator
                .stateSnapshot()
            guard Task.isCancelled == false,
                  let self,
                  reconciliationRevision == revision else { return }
            scheduledReconciliation = nil
            apply(state, reason: reason)
        }
    }

    isolated deinit {
        scheduledReconciliation?.cancel()
    }

    private func apply(
        _ state: SumiPermissionCoordinatorState,
        reason: String
    ) {
        pinningController.reconcile(
            activeQueries: Array(state.activeQueriesByPageId.values),
            windowForPageId: { [windows, windowTabs] pageID in
                BrowserPermissionSettingsRoutes.windowState(
                    displayingPermissionPageId: pageID,
                    in: windows,
                    tabsForDisplay: { window in
                        windowTabs.tabsForDisplay(in: window)
                    }
                )
            },
            windowRegistry: windows,
            reason: reason
        )
    }
}
