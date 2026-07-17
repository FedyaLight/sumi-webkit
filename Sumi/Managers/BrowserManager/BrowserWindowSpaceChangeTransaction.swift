import Foundation

@MainActor
final class BrowserWindowSpaceChangeTransaction {
    private let activation: SpaceActivationService
    private let selection: BrowserWindowSpaceSelectionHandoff
    private let context: BrowserWindowSpaceContextTransition
    private let settlement: BrowserWindowSpaceTransitionSettlement

    init(
        activation: SpaceActivationService,
        selection: BrowserWindowSpaceSelectionHandoff,
        context: BrowserWindowSpaceContextTransition,
        settlement: BrowserWindowSpaceTransitionSettlement
    ) {
        self.activation = activation
        self.selection = selection
        self.context = context
        self.settlement = settlement
    }

    func commit(
        _ space: Space,
        in window: BrowserWindowState,
        identity: SpaceTransitionIdentity?,
        operatesOnActiveWindow: Bool
    ) {
        let target = selection.resolveTarget(for: space, in: window)
        if operatesOnActiveWindow {
            guard activation.setActiveSpace(
                space,
                preferredTab: target.preferredTab,
                contextWindowId: window.id
            ) else { return }
        }

        context.commitContext(space, to: window)
        if operatesOnActiveWindow {
            settlement.synchronizeFocusedSpaceContext(in: window)
        }
        context.completeVisualTransition(
            to: space,
            in: window,
            identity: identity
        )
        selection.present(target, in: window)
        if operatesOnActiveWindow {
            settlement.adoptProfileForSpaceChange(in: window)
        }
        settlement.persist(window)
        settlement.completePendingSplitGroupFocus(
            in: window,
            spaceID: space.id
        )
    }
}
