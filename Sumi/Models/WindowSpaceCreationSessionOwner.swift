//
//  WindowSpaceCreationSessionOwner.swift
//  Sumi
//
//

import Foundation
import Observation

/// Owns the window-local draft session for the Zen-style in-sidebar space creation flow.
///
/// Extracted from `BrowserWindowState` (which otherwise only holds a passive reference)
/// so the begin/finish session lifecycle — including the transient-session-coordinator
/// token bookkeeping — lives in one role-named place instead of being two methods
/// bolted onto the window-state aggregate.
///
/// `@Observable` so `BrowserWindowState` (itself `@Observable`) keeps propagating
/// `activeSession` changes to SwiftUI observers of the owning window state.
@MainActor
@Observable
final class WindowSpaceCreationSessionOwner {
    private(set) var activeSession: SpaceCreationSession?

    @discardableResult
    func begin(
        source: SidebarTransientPresentationSource,
        previousSpaceID: UUID?,
        defaultProfileID: UUID?
    ) -> SpaceCreationSession {
        if let activeSession {
            return activeSession
        }

        let token = source.coordinator?.beginSession(
            kind: .spaceCreation,
            source: source,
            path: "WindowSpaceCreationSessionOwner.begin"
        )
        let session = SpaceCreationSession(
            previousSpaceID: previousSpaceID,
            source: source,
            transientSessionToken: token,
            profileID: defaultProfileID
        )
        activeSession = session
        return session
    }

    func finish(_ session: SpaceCreationSession, reason: String) {
        guard activeSession === session else { return }
        activeSession = nil
        session.source.coordinator?.finishSession(
            session.transientSessionToken,
            reason: reason
        )
    }
}
