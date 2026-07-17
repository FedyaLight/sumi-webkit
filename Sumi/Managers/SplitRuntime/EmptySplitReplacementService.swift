import Foundation

@MainActor
protocol SplitPlaceholderReplacementMutation: AnyObject {
    func isCurrent() -> Bool
    func commitModel() -> Bool
    func settlePresentation()
    func publish()
    func rollback()
}

extension SplitPlaceholderReplacementReceipt: SplitPlaceholderReplacementMutation {}

/// Prepares and commits replacement of one exact registered empty-split
/// placeholder. Drop topology never enters the session/cancellation owner.
@MainActor
final class EmptySplitReplacementService {
    private let replacements: SplitPlaceholderReplacementPlanner
    private let session: EmptySplitSession
    private let terminalMutations: any EmptySplitTerminalMutationAuthority

    init(
        replacements: SplitPlaceholderReplacementPlanner,
        session: EmptySplitSession,
        terminalMutations: any EmptySplitTerminalMutationAuthority
    ) {
        self.replacements = replacements
        self.session = session
        self.terminalMutations = terminalMutations
    }

    @discardableResult
    func replace(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard let receipt = prepareReplacement(with: tab, in: windowState)
        else { return false }
        guard receipt.isCurrent(), receipt.commitModel() else {
            receipt.rollback()
            return false
        }
        receipt.publish()
        return true
    }

    func prepareReplacement(
        with tab: Tab,
        in windowState: BrowserWindowState
    ) -> EmptySplitReplacementReceipt? {
        guard let placeholder = session.placeholder(in: windowState.id),
              let replacement = replacements.prepare(
                  tab: tab,
                  placeholder: placeholder,
                  window: windowState
              ) else { return nil }
        return EmptySplitReplacementReceipt(
            session: session,
            terminalMutations: terminalMutations,
            replacement: replacement,
            placeholder: placeholder,
            windowID: windowState.id
        )
    }
}
