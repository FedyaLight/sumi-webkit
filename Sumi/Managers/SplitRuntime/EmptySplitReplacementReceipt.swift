import Foundation

/// Exact-once aggregate for one registered placeholder and its prepared split
/// replacement. No terminal effect can be omitted at construction.
@MainActor
final class EmptySplitReplacementReceipt: ShortcutPresentationTerminalMutation {
    private enum State {
        case prepared
        case committed
        case published
        case cancelled
    }

    private let session: EmptySplitSession
    private let terminalMutations: any EmptySplitTerminalMutationAuthority
    private let replacement: any SplitPlaceholderReplacementMutation
    private let placeholder: Tab
    private let windowID: UUID
    private var state = State.prepared

    init(
        session: EmptySplitSession,
        terminalMutations: any EmptySplitTerminalMutationAuthority,
        replacement: any SplitPlaceholderReplacementMutation,
        placeholder: Tab,
        windowID: UUID
    ) {
        self.session = session
        self.terminalMutations = terminalMutations
        self.replacement = replacement
        self.placeholder = placeholder
        self.windowID = windowID
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return session.accepts(placeholder, in: windowID)
            && replacement.isCurrent()
    }

    @discardableResult
    func commitModel() -> Bool {
        guard isCurrent() else { return false }
        let committed = terminalMutations.withReversibleSideEffects {
            guard session.consumeAdmitted(placeholder, in: windowID)
            else { return false }
            guard replacement.commitModel() else {
                _ = session.restoreAfterRejectedCommit(
                    placeholder,
                    in: windowID
                )
                return false
            }
            replacement.settlePresentation()
            return true
        }
        guard committed else { return false }
        state = .committed
        return true
    }

    func publish() {
        guard case .committed = state else { return }
        state = .published
        replacement.publish()
    }

    func rollback() {
        guard case .prepared = state else { return }
        state = .cancelled
        replacement.rollback()
    }
}
