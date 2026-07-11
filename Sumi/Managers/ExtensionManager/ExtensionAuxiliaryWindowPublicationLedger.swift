import Foundation

#if DEBUG
    @available(macOS 15.5, *)
    enum ExtensionAuxiliaryPublicationDebugEvent {
        case didOpenWindow(sessionID: UUID)
        case didOpenTab(sessionID: UUID, tabID: UUID)
        case didFocusWindow(sessionID: UUID)
        case didCloseTab(sessionID: UUID, tabID: UUID)
        case didCloseWindow(sessionID: UUID)
    }
#endif

/// Serializes publication and retirement for exact auxiliary-session
/// identities. Entries are removed before WebKit close callbacks, while a
/// short closing claim prevents synchronous re-publication of the same ID.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowPublicationLedger {
    private var publicationsBySessionID: [
        UUID: ExtensionAuxiliaryWindowPublication
    ] = [:]
    private var closingSessionIdentityByID: [UUID: ObjectIdentifier] = [:]

    var sessionIDs: [UUID] {
        Array(publicationsBySessionID.keys)
    }

    func publication(
        for session: AuxiliaryWindowSession
    ) -> ExtensionAuxiliaryWindowPublication? {
        publicationsBySessionID[session.id]
    }

    func isClosing(_ session: AuxiliaryWindowSession) -> Bool {
        closingSessionIdentityByID[session.id] != nil
    }

    func insertPrepared(
        _ publication: ExtensionAuxiliaryWindowPublication,
        for session: AuxiliaryWindowSession
    ) -> Bool {
        guard publicationsBySessionID[session.id] == nil,
              closingSessionIdentityByID[session.id] == nil,
              publication.represents(session)
        else {
            return false
        }
        publicationsBySessionID[session.id] = publication
        return true
    }

    func containsExact(
        _ publication: ExtensionAuxiliaryWindowPublication,
        for session: AuxiliaryWindowSession
    ) -> Bool {
        guard let current = publicationsBySessionID[session.id] else {
            return false
        }
        return current.sessionIdentity == publication.sessionIdentity
            && current.adapter === publication.adapter
            && current.tabReceipt === publication.tabReceipt
            && current.represents(session)
    }

    /// Removes an exact publication and reserves its identity before either
    /// Tab or Window close enters WebKit.
    func claimForRetirement(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession
    ) -> Bool {
        guard containsExact(publication, for: session),
              closingSessionIdentityByID[session.id] == nil
        else {
            return false
        }
        publicationsBySessionID.removeValue(forKey: session.id)
        closingSessionIdentityByID[session.id] = publication.sessionIdentity
        return true
    }

    func finishRetirement(
        _ publication: ExtensionAuxiliaryWindowPublication,
        sessionID: UUID
    ) {
        guard closingSessionIdentityByID[sessionID]
                == publication.sessionIdentity else {
            return
        }
        closingSessionIdentityByID.removeValue(forKey: sessionID)
    }
}
