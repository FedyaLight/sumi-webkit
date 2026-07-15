import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupResidenceOwner {
    private let actionAnchors: ExtensionActionAnchorStore
    private let popupAnchors: ExtensionActionPopupAnchorStore
    private let popupInvocations: ExtensionActionPopupInvocationLedger
    private let popupSessions: ExtensionActionPopupSessionLedger
    private let popupCallbackAdmission: ExtensionActionPopupCallbackAdmission

    init(
        actionAnchors: ExtensionActionAnchorStore,
        popupAnchors: ExtensionActionPopupAnchorStore,
        popupInvocations: ExtensionActionPopupInvocationLedger,
        popupSessions: ExtensionActionPopupSessionLedger,
        popupCallbackAdmission: ExtensionActionPopupCallbackAdmission
    ) {
        self.actionAnchors = actionAnchors
        self.popupAnchors = popupAnchors
        self.popupInvocations = popupInvocations
        self.popupSessions = popupSessions
        self.popupCallbackAdmission = popupCallbackAdmission
    }
}
