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

@MainActor
protocol SplitPlaceholderReplacementPreparing: AnyObject {
    func preparePlaceholderReplacement(
        with tab: Tab,
        placeholder: Tab,
        in windowState: BrowserWindowState
    ) -> (any SplitPlaceholderReplacementMutation)?
}

extension SplitDropService: SplitPlaceholderReplacementPreparing {}

@MainActor
protocol EmptySplitTerminalMutationAuthority: AnyObject {
    func withReversibleSideEffects(_ operation: () -> Bool) -> Bool
}

extension TabStructuralCollectionMutationOwner:
    EmptySplitTerminalMutationAuthority
{}

/// Holds structural observation and lookup publication until exact model and
/// runtime retirement have both reached their terminal state.
@MainActor
protocol EmptySplitStructuralTransactionAuthority: AnyObject {
    func withTransaction<T>(_ operation: () throws -> T) rethrows -> T
}

extension TabStructuralLookupCoordinator:
    EmptySplitStructuralTransactionAuthority
{}

@MainActor
protocol EmptySplitPlaceholderRetirementMutation: AnyObject {
    func isCurrent() -> Bool
    func commitModel() -> Bool
    func publish()
    func rollback()
}

extension EmptySplitPlaceholderRetirementReceipt:
    EmptySplitPlaceholderRetirementMutation
{}

@MainActor
protocol EmptySplitPlaceholderRetirementPreparing: AnyObject {
    func prepareRetirement(
        _ placeholder: Tab
    ) -> (any EmptySplitPlaceholderRetirementMutation)?
}

extension EmptySplitPlaceholderRetirementService:
    EmptySplitPlaceholderRetirementPreparing {
    func prepareRetirement(
        _ placeholder: Tab
    ) -> (any EmptySplitPlaceholderRetirementMutation)? {
        prepare(placeholder)
    }
}

/// Retains the exact ephemeral blank Tab created by the split shortcut. A
/// same-UUID replacement cannot satisfy commit, cancellation, or replacement
/// admission. Structural work stays behind typed transaction participants.
@MainActor
final class EmptySplitSession {
    private let replacements: any SplitPlaceholderReplacementPreparing
    private let structuralTransactions:
        any EmptySplitStructuralTransactionAuthority
    private let terminalMutations: any EmptySplitTerminalMutationAuthority
    private let placeholderRetirement:
        any EmptySplitPlaceholderRetirementPreparing
    private var placeholderByWindowID: [UUID: Tab] = [:]

    init(
        replacements: any SplitPlaceholderReplacementPreparing,
        structuralTransactions:
            any EmptySplitStructuralTransactionAuthority,
        terminalMutations: any EmptySplitTerminalMutationAuthority,
        placeholderRetirement:
            any EmptySplitPlaceholderRetirementPreparing
    ) {
        self.replacements = replacements
        self.structuralTransactions = structuralTransactions
        self.terminalMutations = terminalMutations
        self.placeholderRetirement = placeholderRetirement
    }

    func register(_ placeholder: Tab, in windowID: UUID) {
        placeholderByWindowID[windowID] = placeholder
    }

    func commit(_ placeholder: Tab, in windowID: UUID) {
        _ = consumeAdmitted(placeholder, in: windowID)
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
        guard let placeholder = placeholderByWindowID[windowState.id],
              let replacement = replacements.preparePlaceholderReplacement(
                  with: tab,
                  placeholder: placeholder,
                  in: windowState
              ) else { return nil }
        return EmptySplitReplacementReceipt(
            session: self,
            terminalMutations: terminalMutations,
            replacement: replacement,
            placeholder: placeholder,
            windowID: windowState.id
        )
    }

    @discardableResult
    func cancel(in windowState: BrowserWindowState) -> Bool {
        structuralTransactions.withTransaction {
            guard let placeholder = placeholderByWindowID[windowState.id],
                  let retirement = placeholderRetirement.prepareRetirement(
                      placeholder
                  )
            else { return false }
            let committed = terminalMutations.withReversibleSideEffects {
                guard self.accepts(placeholder, in: windowState.id),
                      retirement.isCurrent(), retirement.commitModel()
                else { return false }
                self.placeholderByWindowID.removeValue(forKey: windowState.id)
                return true
            }
            guard committed else {
                retirement.rollback()
                return false
            }
            retirement.publish()
            return true
        }
    }

    func removeWindow(_ windowID: UUID) {
        placeholderByWindowID.removeValue(forKey: windowID)
    }

    func accepts(_ placeholder: Tab, in windowID: UUID) -> Bool {
        placeholderByWindowID[windowID] === placeholder
    }

    @discardableResult
    func consumeAdmitted(_ placeholder: Tab, in windowID: UUID) -> Bool {
        guard accepts(placeholder, in: windowID) else { return false }
        placeholderByWindowID.removeValue(forKey: windowID)
        return true
    }

    @discardableResult
    func restoreAfterRejectedCommit(
        _ placeholder: Tab,
        in windowID: UUID
    ) -> Bool {
        guard placeholderByWindowID[windowID] == nil else { return false }
        placeholderByWindowID[windowID] = placeholder
        return true
    }
}
