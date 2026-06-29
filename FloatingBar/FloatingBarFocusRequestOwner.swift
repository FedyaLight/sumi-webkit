//
//  FloatingBarFocusRequestOwner.swift
//  Sumi
//
//

import Foundation

@MainActor
final class FloatingBarFocusRequestOwner {
    struct Session: Equatable {
        let windowID: UUID
        let generation: UInt64
    }

    private var generation: UInt64 = 0
    private var currentSession: Session?
    private var deferredFocusTask: Task<Void, Never>?

    deinit {
        deferredFocusTask?.cancel()
    }

    @discardableResult
    func beginSession(windowID: UUID) -> Session {
        generation &+= 1
        deferredFocusTask?.cancel()
        deferredFocusTask = nil

        let session = Session(windowID: windowID, generation: generation)
        currentSession = session
        return session
    }

    func endSession() {
        generation &+= 1
        currentSession = nil
        deferredFocusTask?.cancel()
        deferredFocusTask = nil
    }

    func isCurrent(_ session: Session) -> Bool {
        currentSession == session
    }

    func scheduleDeferredFocus(
        windowID: UUID,
        operation: @escaping @MainActor () -> Void
    ) {
        guard let session = currentSession,
              session.windowID == windowID
        else { return }

        deferredFocusTask?.cancel()
        deferredFocusTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.isCurrent(session)
            else { return }

            self.deferredFocusTask = nil
            operation()
        }
    }
}
