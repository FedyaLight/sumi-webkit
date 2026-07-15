import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPresentationResidenceOwner {
    private let popupCoordinator: ExtensionActionPopupCoordinator
    private let popupAnchorResolver: ExtensionActionPopupAnchorResolver
    private let optionsWindows: ExtensionOptionsWindowService
    private let keyboardCommands: ExtensionKeyboardCommandDispatchOwner

    init(
        popupCoordinator: ExtensionActionPopupCoordinator,
        popupAnchorResolver: ExtensionActionPopupAnchorResolver,
        optionsWindows: ExtensionOptionsWindowService,
        keyboardCommands: ExtensionKeyboardCommandDispatchOwner
    ) {
        self.popupCoordinator = popupCoordinator
        self.popupAnchorResolver = popupAnchorResolver
        self.optionsWindows = optionsWindows
        self.keyboardCommands = keyboardCommands
    }
}
