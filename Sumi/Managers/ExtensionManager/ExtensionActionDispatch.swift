import WebKit

@available(macOS 15.5, *)
enum ExtensionActionDispatchResult {
    case performed(ExtensionActionPopupInvocationRegistration?)
    case stale
    case popupTargetUnavailable
    case awaitingPopupSettlement
    case popupBindingRecoveryRequired(ExtensionContextBindingReceipt)
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionActionDispatching: AnyObject {
    func perform(
        action: WKWebExtension.Action,
        evidence: ExtensionActionInvocationEvidence,
        popupTarget: ExtensionActionPopupInvocationTarget?
    ) -> ExtensionActionDispatchResult
    func cancel(_ registration: ExtensionActionPopupInvocationRegistration?)
}

/// Performs only the final exact WebKit action call. Popup registration and
/// post-call reentrancy settlement live here so no caller can dispatch without
/// the matching invocation tombstone and admission barriers.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionDispatch: ExtensionActionDispatching {
    private let admission: ExtensionActionInvocationAdmission
    private let popupInvocations: ExtensionActionPopupInvocationLedger

    init(
        admission: ExtensionActionInvocationAdmission,
        popupInvocations: ExtensionActionPopupInvocationLedger
    ) {
        self.admission = admission
        self.popupInvocations = popupInvocations
    }

    func perform(
        action: WKWebExtension.Action,
        evidence: ExtensionActionInvocationEvidence,
        popupTarget: ExtensionActionPopupInvocationTarget?
    ) -> ExtensionActionDispatchResult {
        guard admission.isCurrent(evidence) else { return .stale }

        let registration: ExtensionActionPopupInvocationRegistration?
        if action.presentsPopup {
            guard let popupTarget else { return .popupTargetUnavailable }
            switch popupInvocations.register(
                evidence: evidence,
                action: action,
                target: popupTarget
            ) {
            case .registered(let exactRegistration):
                registration = exactRegistration
            case .awaitingSettlement:
                return .awaitingPopupSettlement
            case .recoveryRequired(let receipt):
                return .popupBindingRecoveryRequired(receipt)
            }
        } else {
            registration = nil
        }

        guard admission.isCurrent(evidence) else {
            cancel(registration)
            return .stale
        }
        evidence.context.performAction(for: evidence.adapter)
        guard admission.isCurrent(evidence) else {
            cancel(registration)
            return .stale
        }
        return .performed(registration)
    }

    func cancel(
        _ registration: ExtensionActionPopupInvocationRegistration?
    ) {
        guard let registration else { return }
        popupInvocations.cancel(registration)
    }
}
