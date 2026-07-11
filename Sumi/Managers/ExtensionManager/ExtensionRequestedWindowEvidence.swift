import Foundation
import WebKit

/// Validates exact explicitly requested WebExtension window identities and
/// committed auxiliary publications. It never chooses a fallback target.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedWindowEvidence {
    enum Projection {
        case normal(BrowserWindowState)
        case auxiliary(AuxiliaryWindowSession)
    }

    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let publications: ExtensionWindowPublicationQuery

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        publications: ExtensionWindowPublicationQuery
    ) {
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.publications = publications
    }

    func explicitProjection(
        for requestedWindow: any WKWebExtensionWindow,
        extensionContext: WKWebExtensionContext?,
        browser: any ExtensionTabTargetQuery
    ) throws -> Projection {
        if let adapter = requestedWindow as? ExtensionMiniWindowAdapter,
           let extensionContext,
           let session = publishedMiniWindowSession(
               for: adapter,
               extensionContext: extensionContext,
               browser: browser
           ) {
            return .auxiliary(session)
        }

        if let adapter = requestedWindow as? ExtensionWindowAdapter,
           let extensionContext,
           let identity = currentIdentity(for: extensionContext),
           let window = browser.extensionWindowState(
               for: adapter.windowId
           ), profileRuntime.windowMatchesProfile(
               window,
               profileId: identity.profileID,
               runtime: runtime()
           ), publications.publishedWindowAdapter(
               for: window,
               profileID: identity.profileID
           ) === adapter {
            return .normal(window)
        }

        throw ExtensionManagerCallbackError
            .requestedTabUnavailable.nsError()
    }

    func firstPublishedMiniWindowSession(
        for extensionContext: WKWebExtensionContext,
        browser: any ExtensionTabTargetQuery
    ) -> AuxiliaryWindowSession? {
        guard let identity = currentIdentity(for: extensionContext),
              let adapter = publications.publishedAuxiliaryWindowAdapters(
            ownerExtensionID: identity.extensionID,
            profileID: identity.profileID
        ).first else {
            return nil
        }
        return publishedMiniWindowSession(
            for: adapter,
            extensionContext: extensionContext,
            browser: browser
        )
    }

    private func publishedMiniWindowSession(
        for adapter: ExtensionMiniWindowAdapter,
        extensionContext: WKWebExtensionContext,
        browser: any ExtensionTabTargetQuery
    ) -> AuxiliaryWindowSession? {
        guard let identity = currentIdentity(for: extensionContext),
              publications.publishedAuxiliaryWindowAdapters(
            ownerExtensionID: identity.extensionID,
            profileID: identity.profileID
        ).contains(where: { $0 === adapter }),
              let session = browser.auxiliaryWindowSession(
                  for: adapter.sessionId
              ), session.id == adapter.sessionId,
              session.miniWindowAdapter === adapter,
              session.ownerExtensionID == identity.extensionID,
              profileRuntime.resolvedProfileId(
                  for: session.tab,
                  runtime: runtime()
              ) == identity.profileID,
              ownerContext(
                  for: session,
                  extensionID: identity.extensionID,
                  profileID: identity.profileID
              ) === extensionContext
        else {
            return nil
        }
        return session
    }

    func currentIdentity(
        for context: WKWebExtensionContext
    ) -> (extensionID: String, profileID: UUID)? {
        guard let identity = profileRuntime.exactContextIdentity(for: context)
        else {
            return nil
        }
        return (identity.extensionId, identity.profileId)
    }

    private func ownerContext(
        for session: AuxiliaryWindowSession,
        extensionID: String,
        profileID: UUID
    ) -> WKWebExtensionContext? {
        session.tab.webExtensionContextOverride
            ?? profileRuntime.contexts(for: profileID)[extensionID]
    }
}
