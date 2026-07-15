import Foundation
import SumiDomain

/// Creates and compensates the regular Tab used as an empty split placeholder.
/// Space selection and regular-Tab lifecycle stay behind one exact capability.
@MainActor
final class EmptySplitPlaceholderFactory {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: TabRegularLifecycleOwner
    private let retirement: any EmptySplitPlaceholderRetirementPreparing
    private let structuralTransactions:
        any EmptySplitStructuralTransactionAuthority
    private let terminalMutations: any EmptySplitTerminalMutationAuthority

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: TabRegularLifecycleOwner,
        retirement: any EmptySplitPlaceholderRetirementPreparing,
        structuralTransactions:
            any EmptySplitStructuralTransactionAuthority,
        terminalMutations: any EmptySplitTerminalMutationAuthority
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.retirement = retirement
        self.structuralTransactions = structuralTransactions
        self.terminalMutations = terminalMutations
    }

    func create(in windowState: BrowserWindowState) -> Tab {
        let targetSpace = windowState.currentSpaceId.flatMap(spaces.space(with:))
            ?? spaces.currentSpace
        return regularTabs.createNewTab(
            url: SumiSurface.emptyTabURL.absoluteString,
            in: targetSpace,
            activate: false
        )
    }

    @discardableResult
    func discard(_ placeholder: Tab) -> Bool {
        structuralTransactions.withTransaction {
            guard let receipt = retirement.prepareRetirement(placeholder)
            else { return false }
            let committed = terminalMutations.withReversibleSideEffects {
                receipt.isCurrent() && receipt.commitModel()
            }
            guard committed else {
                receipt.rollback()
                return false
            }
            receipt.publish()
            return true
        }
    }
}

/// Creates and resolves the temporary blank member used by the “add split”
/// command. It composes exact creation, insertion, activation, and session
/// participants and retains no TabManager locator.
@MainActor
final class EmptySplitService {
    private let placeholders: EmptySplitPlaceholderFactory
    private let insertion: SplitInsertionService
    private let activations: ShortcutPresentationActivationService
    private let session: EmptySplitSession

    init(
        placeholders: EmptySplitPlaceholderFactory,
        insertion: SplitInsertionService,
        activations: ShortcutPresentationActivationService,
        session: EmptySplitSession
    ) {
        self.placeholders = placeholders
        self.insertion = insertion
        self.activations = activations
        self.session = session
    }

    @discardableResult
    func create(
        side: SplitDropSide,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let admission = insertion.admission(
            side: side,
            in: windowState
        ) else { return false }
        let placeholder = placeholders.create(in: windowState)
        guard insertion.enterSplit(
            with: placeholder,
            admission: admission,
            in: windowState
        ) else {
            _ = placeholders.discard(placeholder)
            return false
        }
        session.register(placeholder, in: windowState.id)
        return true
    }

    func commit(_ placeholder: Tab, in windowID: UUID) {
        session.commit(placeholder, in: windowID)
    }

    func replace(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        activations.commitActivation(
            tab,
            in: windowState.id,
            presentationSpaceID: tab.spaceId ?? windowState.currentSpaceId
        ) { [self] admitted in
            prepareReplacementCommit(with: admitted, in: windowState)
        }
    }

    func prepareReplacementCommit(
        with tab: Tab,
        in windowState: BrowserWindowState
    ) -> EmptySplitReplacementReceipt? {
        session.prepareReplacement(with: tab, in: windowState)
    }

    func cancel(in windowState: BrowserWindowState) -> Bool {
        session.cancel(in: windowState)
    }

    func removeWindow(_ windowID: UUID) {
        session.removeWindow(windowID)
    }
}
