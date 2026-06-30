import Foundation

@MainActor
final class FloatingBarDeferredTextOwner {
    typealias DeferredScheduler = @MainActor (_ operation: @escaping @MainActor () -> Void) -> Void

    private struct Session: Equatable {
        let windowID: UUID
        let generation: UInt64
    }

    private struct PendingChange: Equatable {
        let session: Session
        let generation: UInt64
    }

    private var session: Session?
    private var pendingChange: PendingChange?
    private var nextSessionGeneration: UInt64 = 0
    private var nextPendingGeneration: UInt64 = 0

    func beginSession(windowID: UUID) {
        nextSessionGeneration &+= 1
        session = Session(windowID: windowID, generation: nextSessionGeneration)
        pendingChange = nil
    }

    func endSession() {
        nextSessionGeneration &+= 1
        session = nil
        pendingChange = nil
    }

    @discardableResult
    func scheduleTextChange(
        in windowState: BrowserWindowState,
        text: String,
        scheduler: DeferredScheduler = FloatingBarDeferredTextOwner.scheduleOnNextMainTurn,
        apply: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard windowState.isFloatingBarVisible,
              let session,
              session.windowID == windowState.id
        else {
            return false
        }

        nextPendingGeneration &+= 1
        let pendingChange = PendingChange(session: session, generation: nextPendingGeneration)
        self.pendingChange = pendingChange

        scheduler { [weak self, weak windowState] in
            guard let self,
                  let windowState,
                  windowState.isFloatingBarVisible,
                  self.session == session,
                  self.pendingChange == pendingChange
            else {
                return
            }

            self.pendingChange = nil
            apply(text)
        }
        return true
    }

    private static func scheduleOnNextMainTurn(_ operation: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            operation()
        }
    }
}
