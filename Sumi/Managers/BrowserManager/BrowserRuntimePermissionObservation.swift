import Foundation

@MainActor
final class BrowserRuntimePermissionObservation {
    private let permissionRuntime: BrowserManagerPermissionRuntime
    private let sidebarPinning: BrowserPermissionSidebarPinningOwner

    init(
        permissionRuntime: BrowserManagerPermissionRuntime,
        sidebarPinning: BrowserPermissionSidebarPinningOwner
    ) {
        self.permissionRuntime = permissionRuntime
        self.sidebarPinning = sidebarPinning
    }

    func start() {
        permissionRuntime.startPermissionEventObservation {
            [weak sidebarPinning] _ in
            await sidebarPinning?.reconcile(reason: "permission-event")
        }
    }

    func cancel() {
        permissionRuntime.cancelPermissionEventObservation()
    }
}
