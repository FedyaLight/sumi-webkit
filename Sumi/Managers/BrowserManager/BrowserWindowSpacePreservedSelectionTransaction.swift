import Foundation

@MainActor
final class BrowserWindowSpacePreservedSelectionTransaction {
    private let selection: BrowserWindowSpaceSelectionHandoff
    private let context: BrowserWindowSpaceContextTransition
    private let settlement: BrowserWindowSpaceTransitionSettlement

    init(
        selection: BrowserWindowSpaceSelectionHandoff,
        context: BrowserWindowSpaceContextTransition,
        settlement: BrowserWindowSpaceTransitionSettlement
    ) {
        self.selection = selection
        self.context = context
        self.settlement = settlement
    }

    func commitIfPossible(
        _ space: Space,
        in window: BrowserWindowState,
        operatesOnActiveWindow: Bool
    ) -> Bool {
        guard window.currentSpaceId == space.id,
              selection.canPreserveCurrentSelection(in: window)
        else { return false }

        context.sanitizePreservedSelection(in: window)
        context.commitContext(space, to: window)
        if operatesOnActiveWindow {
            settlement.synchronizeFocusedSpaceContext(in: window)
        }
        context.completePreservedSelectionRefresh(in: window)
        settlement.persist(window)
        return true
    }
}
