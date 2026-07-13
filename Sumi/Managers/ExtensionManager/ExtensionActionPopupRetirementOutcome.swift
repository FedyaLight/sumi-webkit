import Foundation

@available(macOS 15.5, *)
struct ExtensionActionPopupPendingRetirement {
    let task: Task<Void, Never>?
    let sessionRetirement: ExtensionActionPopupSessionRetirement?
    let inheritedFocusReceipt: ExtensionActionPopupFocusReceipt?
    let focusRevision: UInt64
    let completion: ExtensionActionPopupCompletion
    let error: Error
    let restoresFocus: Bool
}

@available(macOS 15.5, *)
struct ExtensionActionPopupSessionRetirement {
    let session: ExtensionActionPopupSession
    let closePhysicalPopup: Bool
    let awaitPopoverDidClose: Bool
    let focusRevision: UInt64
    let restoresFocus: Bool
    let replacementVisible: Bool
}

@available(macOS 15.5, *)
struct ExtensionActionPopupClosingCompletion {
    let session: ExtensionActionPopupSession
    let focusRevision: UInt64
    let restoresFocus: Bool
}

@available(macOS 15.5, *)
final class ExtensionActionPopupRetirementOutcome {
    enum Payload {
        case pending(ExtensionActionPopupPendingRetirement)
        case session(ExtensionActionPopupSessionRetirement)
        case closingFinished(ExtensionActionPopupClosingCompletion)
    }

    private var payload: Payload?

    private init(_ payload: Payload) {
        self.payload = payload
    }

    static func pending(
        _ pending: ExtensionActionPopupPendingRetirement
    ) -> ExtensionActionPopupRetirementOutcome {
        .init(.pending(pending))
    }

    static func session(
        _ session: ExtensionActionPopupSessionRetirement
    ) -> ExtensionActionPopupRetirementOutcome {
        .init(.session(session))
    }

    static func closingFinished(
        _ completion: ExtensionActionPopupClosingCompletion
    ) -> ExtensionActionPopupRetirementOutcome {
        .init(.closingFinished(completion))
    }

    func take() -> Payload? {
        defer { payload = nil }
        return payload
    }
}

@available(macOS 15.5, *)
struct ExtensionActionPopupActivation {
    let superseded: ExtensionActionPopupRetirementOutcome?
}

@available(macOS 15.5, *)
struct ExtensionActionPopupCommit {
    let phase: SafariExtensionPopupLifecyclePhase
    let replaced: ExtensionActionPopupRetirementOutcome?
}
