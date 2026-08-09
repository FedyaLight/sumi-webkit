import Foundation

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
    func withTransaction<T>(
        _ operation: @MainActor @Sendable () throws -> T
    ) rethrows -> T
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

@MainActor
protocol EmptySplitConvertedPlaceholderRetiring: AnyObject {
    func retire(_ placeholder: Tab, in windowID: UUID) -> Bool
}

@MainActor
final class EmptySplitConvertedPlaceholderRetirementService:
    EmptySplitConvertedPlaceholderRetiring {
    private let pins: ShortcutPinCollectionStateOwner
    private let liveShortcuts: LiveShortcutTabRegistry
    private let retirement: ShortcutPinRetirementTransaction

    init(
        pins: ShortcutPinCollectionStateOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        retirement: ShortcutPinRetirementTransaction
    ) {
        self.pins = pins
        self.liveShortcuts = liveShortcuts
        self.retirement = retirement
    }

    func retire(_ placeholder: Tab, in windowID: UUID) -> Bool {
        guard let pinID = placeholder.shortcutPinId,
              liveShortcuts.tab(for: pinID, in: windowID) === placeholder,
              let pin = pins.shortcutPin(by: pinID)
        else { return false }
        return retirement.remove([pin], presentNotification: false)
    }
}

/// Retains the exact ephemeral blank Tab created by the split shortcut. A
/// same-UUID replacement cannot satisfy commit, cancellation, or replacement
/// admission. Structural work stays behind typed transaction participants.
@MainActor
final class EmptySplitSession {
    private let structuralTransactions:
        any EmptySplitStructuralTransactionAuthority
    private let terminalMutations: any EmptySplitTerminalMutationAuthority
    private let placeholderRetirement:
        any EmptySplitPlaceholderRetirementPreparing
    private let convertedPlaceholderRetirement:
        (any EmptySplitConvertedPlaceholderRetiring)?
    private var placeholderByWindowID: [UUID: Tab] = [:]

    init(
        structuralTransactions:
            any EmptySplitStructuralTransactionAuthority,
        terminalMutations: any EmptySplitTerminalMutationAuthority,
        placeholderRetirement:
            any EmptySplitPlaceholderRetirementPreparing,
        convertedPlaceholderRetirement:
            (any EmptySplitConvertedPlaceholderRetiring)? = nil
    ) {
        self.structuralTransactions = structuralTransactions
        self.terminalMutations = terminalMutations
        self.placeholderRetirement = placeholderRetirement
        self.convertedPlaceholderRetirement = convertedPlaceholderRetirement
    }

    func register(_ placeholder: Tab, in windowID: UUID) {
        placeholderByWindowID[windowID] = placeholder
    }

    func commit(_ placeholder: Tab, in windowID: UUID) {
        _ = consumeAdmitted(placeholder, in: windowID)
    }

    @discardableResult
    func cancel(in windowState: BrowserWindowState) -> Bool {
        guard let placeholder = placeholderByWindowID[windowState.id] else {
            return false
        }
        if placeholder.shortcutPinId != nil {
            guard let convertedPlaceholderRetirement,
                  accepts(placeholder, in: windowState.id)
            else { return false }
            placeholderByWindowID.removeValue(forKey: windowState.id)
            guard convertedPlaceholderRetirement.retire(
                placeholder,
                in: windowState.id
            ) else {
                _ = restoreAfterRejectedCommit(
                    placeholder,
                    in: windowState.id
                )
                return false
            }
            return true
        }
        return structuralTransactions.withTransaction {
            guard let retirement = placeholderRetirement.prepareRetirement(
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

    func placeholder(in windowID: UUID) -> Tab? {
        placeholderByWindowID[windowID]
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
