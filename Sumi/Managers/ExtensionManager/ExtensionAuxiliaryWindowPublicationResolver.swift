import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionAuxiliaryWindowPublication {
    let sessionIdentity: ObjectIdentifier
    let profileID: UUID
    let ownerExtensionID: String
    let context: WKWebExtensionContext
    let adapter: ExtensionMiniWindowAdapter
    let tabReceipt: ExtensionAuxiliaryTabPublicationReceipt

    func represents(_ session: AuxiliaryWindowSession) -> Bool {
        sessionIdentity == ObjectIdentifier(session)
            && adapter === session.miniWindowAdapter
            && tabReceipt.represents(
                tab: session.tab,
                webView: session.webView
            )
    }
}

/// Resolves and revalidates the exact browser/runtime facts required for one
/// auxiliary WebKit window publication. Event ordering and ledger mutation
/// remain in `ExtensionAuxiliaryWindowLifecycle`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowPublicationResolver {
    private let adapterStore: ExtensionBrowserAdapterStore
    private let profileRuntime: ExtensionProfileRuntime
    private let tabPublication:
        any ExtensionAuxiliaryTabPublicationPreparing

    init(
        adapterStore: ExtensionBrowserAdapterStore,
        profileRuntime: ExtensionProfileRuntime,
        tabPublication: any ExtensionAuxiliaryTabPublicationPreparing
    ) {
        self.adapterStore = adapterStore
        self.profileRuntime = profileRuntime
        self.tabPublication = tabPublication
    }

    func resolvePublication(
        for session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionAuxiliaryWindowPublication? {
        guard let control,
              control.auxiliaryWindowSession(for: session.id) === session,
              let adapter = session.miniWindowAdapter,
              adapterStore.existingMiniWindowAdapter(for: session.id)
                === adapter,
              let profileID = profileRuntime.resolvedProfileId(
                  for: session.tab,
                  runtime: runtime
              ),
              let ownerExtensionID = session.ownerExtensionID,
              let context = ownerContext(
                  for: session,
                  profileID: profileID
              ),
              let tabReceipt = tabPublication.prepareTabPublication(
                  for: session,
                  profileID: profileID,
                  ownerExtensionID: ownerExtensionID,
                  ownerContext: context,
                  runtime: runtime
              )
        else {
            return nil
        }
        return ExtensionAuxiliaryWindowPublication(
            sessionIdentity: ObjectIdentifier(session),
            profileID: profileID,
            ownerExtensionID: ownerExtensionID,
            context: context,
            adapter: adapter,
            tabReceipt: tabReceipt
        )
    }

    func projectionIsCurrent(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        guard publication.represents(session),
              control?.auxiliaryWindowSession(for: session.id) === session,
              adapterStore.existingMiniWindowAdapter(for: session.id)
                === publication.adapter,
              profileRuntime.resolvedProfileId(
                  for: session.tab,
                  runtime: runtime
              ) == publication.profileID,
              ownerContext(
                  for: session,
                  profileID: publication.profileID
              ) === publication.context,
              session.ownerExtensionID == publication.ownerExtensionID,
              publication.tabReceipt.isCurrent(runtime: runtime)
        else {
            return false
        }
        return true
    }

    func publicationIsCurrent(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        projectionIsCurrent(
            publication,
            session: session,
            runtime: runtime,
            control: control
        ) && publication.context.openWindows.contains { openWindow in
            (openWindow as AnyObject) === publication.adapter
        }
    }

    func windowMatchesProfile(
        _ window: BrowserWindowState,
        publication: ExtensionAuxiliaryWindowPublication,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        profileRuntime.resolvedProfileId(
            for: window,
            runtime: runtime
        ) == publication.profileID
    }

    private func ownerContext(
        for session: AuxiliaryWindowSession,
        profileID: UUID
    ) -> WKWebExtensionContext? {
        if let override = session.tab.webExtensionContextOverride {
            guard let ownerExtensionID = session.ownerExtensionID,
                  profileRuntime.contexts(for: profileID)[ownerExtensionID]
                    === override,
                  profileRuntime.profileId(for: override) == profileID,
                  profileRuntime.extensionId(for: override)
                    == ownerExtensionID else {
                return nil
            }
            return override
        }
        guard let ownerExtensionID = session.ownerExtensionID else {
            return nil
        }
        return profileRuntime.contexts(for: profileID)[ownerExtensionID]
    }
}
