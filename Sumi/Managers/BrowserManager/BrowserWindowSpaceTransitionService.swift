import Foundation

/// Orders one window's Space transition across process selection, window
/// context, visible content, profile adoption, and durable session state.
@MainActor
final class BrowserWindowSpaceTransitionService {
    private let spaceActivation: SpaceActivationService
    private let isActiveWindow: (BrowserWindowState) -> Bool
    private let selectionHandoff: BrowserWindowSpaceSelectionHandoff
    private let contextTransition: BrowserWindowSpaceContextTransition
    private let synchronizeFocusedSpaceContext: (BrowserWindowState) -> Void
    private let adoptProfileForSpaceChange: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void
    private let completePendingSplitGroupFocus: (BrowserWindowState, UUID) -> Void

    init(
        spaceActivation: SpaceActivationService,
        isActiveWindow: @escaping (BrowserWindowState) -> Bool,
        selectionHandoff: BrowserWindowSpaceSelectionHandoff,
        contextTransition: BrowserWindowSpaceContextTransition,
        synchronizeFocusedSpaceContext: @escaping (BrowserWindowState) -> Void,
        adoptProfileForSpaceChange: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        completePendingSplitGroupFocus: @escaping (BrowserWindowState, UUID) -> Void
    ) {
        self.spaceActivation = spaceActivation
        self.isActiveWindow = isActiveWindow
        self.selectionHandoff = selectionHandoff
        self.contextTransition = contextTransition
        self.synchronizeFocusedSpaceContext = synchronizeFocusedSpaceContext
        self.adoptProfileForSpaceChange = adoptProfileForSpaceChange
        self.persistWindowSession = persistWindowSession
        self.completePendingSplitGroupFocus = completePendingSplitGroupFocus
    }

    func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        completingTransition identity: SpaceTransitionIdentity? = nil
    ) {
        guard isValidTransition(identity, to: space, in: windowState) else {
            return
        }

        let operatesOnActiveWindow = isActiveWindow(windowState)
        if identity == nil,
           windowState.currentSpaceId == space.id,
           selectionHandoff.canPreserveCurrentSelection(in: windowState) {
            contextTransition.sanitizePreservedSelection(in: windowState)
            contextTransition.commitContext(space, to: windowState)
            if operatesOnActiveWindow {
                synchronizeFocusedSpaceContext(windowState)
            }
            contextTransition.completePreservedSelectionRefresh(in: windowState)
            persistWindowSession(windowState)
            return
        }

        let target = selectionHandoff.resolveTarget(for: space, in: windowState)
        if operatesOnActiveWindow {
            spaceActivation.setActiveSpace(
                space,
                preferredTab: target.preferredTab,
                contextWindowId: windowState.id
            )
        }

        contextTransition.commitContext(space, to: windowState)
        if operatesOnActiveWindow {
            synchronizeFocusedSpaceContext(windowState)
        }
        contextTransition.completeVisualTransition(
            to: space,
            in: windowState,
            identity: identity
        )
        selectionHandoff.present(target, in: windowState)

        if operatesOnActiveWindow {
            adoptProfileForSpaceChange(windowState)
        }
        persistWindowSession(windowState)
        completePendingSplitGroupFocus(windowState, space.id)
    }

    private func isValidTransition(
        _ identity: SpaceTransitionIdentity?,
        to space: Space,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let identity else { return true }
        return identity.destinationSpaceId == space.id
            && windowState.windowThemeState
                .matchesInteractiveSpaceTransition(identity)
    }
}
