import Foundation

/// Orders one window's Space transition across process selection, window
/// context, visible content, profile adoption, and durable session state.
@MainActor
final class BrowserWindowSpaceTransitionService {
    private let spaceActivation: SpaceActivationService
    private let preservedSelection: BrowserWindowSpacePreservedSelectionTransaction
    private let spaceChange: BrowserWindowSpaceChangeTransaction
    private let settlement: BrowserWindowSpaceTransitionSettlement

    init(
        spaceActivation: SpaceActivationService,
        preservedSelection: BrowserWindowSpacePreservedSelectionTransaction,
        spaceChange: BrowserWindowSpaceChangeTransaction,
        settlement: BrowserWindowSpaceTransitionSettlement
    ) {
        self.spaceActivation = spaceActivation
        self.preservedSelection = preservedSelection
        self.spaceChange = spaceChange
        self.settlement = settlement
    }

    func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        completingTransition identity: SpaceTransitionIdentity? = nil
    ) {
        guard let windowReceipt = settlement.admit(windowState) else {
            return
        }
        setActiveSpace(
            space,
            in: windowState,
            admittedBy: windowReceipt,
            completingTransition: identity
        )
    }

    private func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        admittedBy windowReceipt: WindowRegistry.WindowRegistrationReceipt,
        completingTransition identity: SpaceTransitionIdentity?
    ) {
        guard settlement.resolve(windowReceipt) === windowState else {
            return
        }
        guard windowState.windowThemeState.acceptsInteractiveCompletion(
            identity: identity,
            destinationSpaceID: space.id
        ) else {
            return
        }

        guard spaceActivation.admitProfileIfNeeded(
            for: space,
            retry: { [weak self, weak space] in
                guard let self,
                      let space,
                      let currentWindow = settlement.resolve(windowReceipt)
                else { return }
                self.setActiveSpace(
                    space,
                    in: currentWindow,
                    admittedBy: windowReceipt,
                    completingTransition: identity
                )
            }
        ) else { return }

        let operatesOnActiveWindow = settlement.isActiveWindow(windowState)
        if identity == nil,
           preservedSelection.commitIfPossible(
               space,
               in: windowState,
               operatesOnActiveWindow: operatesOnActiveWindow
           ) {
            return
        }
        spaceChange.commit(
            space,
            in: windowState,
            identity: identity,
            operatesOnActiveWindow: operatesOnActiveWindow
        )
    }
}
