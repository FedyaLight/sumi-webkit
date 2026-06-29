import AppKit

@MainActor
final class FloatingBarInteractionCommitOwner {
    typealias DeferredScheduler = @MainActor (_ operation: @escaping @MainActor () -> Void) -> Void

    private struct Session: Equatable {
        let windowID: UUID
        let generation: UInt64
    }

    private weak var cardView: NSView?
    private var session: Session?
    private var pendingMutationSession: Session?
    private var nextGeneration: UInt64 = 0

    func beginSession(windowID: UUID) {
        nextGeneration &+= 1
        session = Session(windowID: windowID, generation: nextGeneration)
        pendingMutationSession = nil
    }

    func endSession() {
        nextGeneration &+= 1
        session = nil
        pendingMutationSession = nil
        cardView = nil
    }

    func updateCardView(_ view: NSView) {
        cardView = view
    }

    func isEventInsideCard(_ event: NSEvent) -> Bool {
        FloatingBarOutsideClickRouting.isEventInsideCard(event, cardView: cardView)
    }

    func isLocationInsideCard(_ locationInWindow: NSPoint) -> Bool {
        FloatingBarOutsideClickRouting.isLocationInsideCard(
            locationInWindow,
            cardView: cardView
        )
    }

    func monitorResult(
        for event: NSEvent,
        isFloatingBarVisible: Bool,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        FloatingBarOutsideClickRouting.monitorResult(
            for: event,
            isFloatingBarVisible: isFloatingBarVisible,
            isEventInsideCard: isEventInsideCard(event),
            onOutsideClick: onOutsideClick
        )
    }

    @discardableResult
    func requestCommit(
        in windowState: BrowserWindowState,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestCommit(
            in: windowState,
            scheduler: FloatingBarInteractionCommitOwner.scheduleOnNextMainTurn,
            perform: perform
        )
    }

    @discardableResult
    func requestCommit(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestDeferredMutation(
            in: windowState,
            scheduler: scheduler,
            perform: perform
        )
    }

    @discardableResult
    func requestDismiss(
        in windowState: BrowserWindowState,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestDismiss(
            in: windowState,
            scheduler: FloatingBarInteractionCommitOwner.scheduleOnNextMainTurn,
            perform: perform
        )
    }

    @discardableResult
    func requestDismiss(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestDeferredMutation(
            in: windowState,
            scheduler: scheduler,
            perform: perform
        )
    }

    private func requestDeferredMutation(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        guard windowState.isFloatingBarVisible,
              let session,
              session.windowID == windowState.id,
              pendingMutationSession == nil
        else {
            return false
        }

        pendingMutationSession = session
        scheduler { [weak self, weak windowState] in
            guard let self,
                  let windowState,
                  windowState.isFloatingBarVisible,
                  self.session == session,
                  self.pendingMutationSession == session
            else {
                return
            }

            perform()
        }
        return true
    }

    private static func scheduleOnNextMainTurn(_ operation: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            operation()
        }
    }
}
