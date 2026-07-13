import Foundation

/// Quarantines one exact popup runtime before WebKit unload and removes its
/// invocation tombstone only after that physical binding is gone.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupRuntimeRetirement {
    private let sessions: ExtensionActionPopupRetirementService
    private let invocations: ExtensionActionPopupInvocationLedger

    init(
        sessions: ExtensionActionPopupRetirementService,
        invocations: ExtensionActionPopupInvocationLedger
    ) {
        self.sessions = sessions
        self.invocations = invocations
    }

    func begin(_ receipt: ExtensionContextBindingReceipt) {
        sessions.retire(binding: receipt)
        invocations.quarantine(binding: receipt)
    }

    func complete(_ receipt: ExtensionContextBindingReceipt) {
        invocations.retire(binding: receipt)
    }
}
