import Foundation

/// Installs the one-shot browser callback routes only after every requested-
/// tab and options role is complete.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerBrowserRouteInstaller {
    private let delegateBridge: ExtensionControllerDelegateBridge
    private let actionSurfaces: ExtensionActionSurfacePublisher
    private let popupAdmission: ExtensionActionPopupCallbackAdmission
    private let popupInvocations: ExtensionActionPopupInvocationLedger
    private let popupCoordinator: ExtensionActionPopupCoordinator
    private let optionsWindows: ExtensionOptionsWindowService

    init(
        delegateBridge: ExtensionControllerDelegateBridge,
        actionSurfaces: ExtensionActionSurfacePublisher,
        popupAdmission: ExtensionActionPopupCallbackAdmission,
        popupInvocations: ExtensionActionPopupInvocationLedger,
        popupCoordinator: ExtensionActionPopupCoordinator,
        optionsWindows: ExtensionOptionsWindowService
    ) {
        self.delegateBridge = delegateBridge
        self.actionSurfaces = actionSurfaces
        self.popupAdmission = popupAdmission
        self.popupInvocations = popupInvocations
        self.popupCoordinator = popupCoordinator
        self.optionsWindows = optionsWindows
    }

    func install(
        requestedTabs: ExtensionRequestedBrowserRuntimeServices,
        optionsComposer: ExtensionOptionsWindowCallbackComposer
    ) -> Bool {
        let routes = ExtensionControllerDelegateBrowserRoutes(
            actionSurfaces: actionSurfaces,
            actionPopupCallbackAdmission: popupAdmission,
            actionPopupInvocationLedger: popupInvocations,
            actionPopupCoordinator: popupCoordinator,
            windows: requestedTabs.windowVisibility,
            opening: requestedTabs.openingCallbacks,
            optionsComposer: optionsComposer,
            optionsWindows: optionsWindows
        )
        return delegateBridge.installBrowserRoutes(routes) != nil
    }
}
