import Foundation
import WebKit

/// Read-only projection of exact auxiliary Window+Tab publications. It may
/// observe a prepared Tab receipt only while the owner context has already
/// admitted the matching Window, allowing WebKit to query `tabs` reentrantly
/// from `didOpenWindow` without granting any unrelated context access.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowPublicationQuery {
    private let ledger: ExtensionAuxiliaryWindowPublicationLedger
    private let resolver: ExtensionAuxiliaryWindowPublicationResolver
    private let opening: ExtensionAuxiliaryWindowOpeningTransaction

    init(
        ledger: ExtensionAuxiliaryWindowPublicationLedger,
        resolver: ExtensionAuxiliaryWindowPublicationResolver,
        opening: ExtensionAuxiliaryWindowOpeningTransaction
    ) {
        self.ledger = ledger
        self.resolver = resolver
        self.opening = opening
    }

    func publishedAdapters(
        ownerExtensionID: String,
        profileID: UUID,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> [ExtensionMiniWindowAdapter] {
        guard let control else { return [] }
        return ledger.sessionIDs.compactMap { sessionID in
            guard let session = control.auxiliaryWindowSession(for: sessionID),
                  session.window.isVisible,
                  let publication = opening.committedPublication(
                      for: session,
                      runtime: runtime,
                      control: control
                  ),
                  publication.profileID == profileID,
                  publication.ownerExtensionID == ownerExtensionID else {
                return nil
            }
            return publication.adapter
        }
    }

    func isCommittedTabAdapter(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab,
        visibleTo context: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        guard let control,
              let session = control.auxiliaryWindowSession(for: tab),
              session.tab === tab,
              let publication = opening.committedPublication(
                  for: session,
                  runtime: runtime,
                  control: control
              ) else {
            return false
        }
        return publication.context === context
            && publication.tabReceipt.adapter === adapter
    }

    func isCurrentWindowAdapter(
        _ adapter: ExtensionMiniWindowAdapter,
        visibleTo context: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        currentPublication(
            for: adapter,
            visibleTo: context,
            runtime: runtime,
            control: control
        ) != nil
    }

    func tabAdapter(
        for adapter: ExtensionMiniWindowAdapter,
        visibleTo context: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionTabAdapter? {
        currentPublication(
            for: adapter,
            visibleTo: context,
            runtime: runtime,
            control: control
        )?.tabReceipt.adapter
    }

    func canUseCommittedTabPublication(
        for tab: Tab,
        profileID: UUID? = nil,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        guard let control,
              let session = control.auxiliaryWindowSession(for: tab),
              session.tab === tab,
              let publication = opening.committedPublication(
                  for: session,
                  runtime: runtime,
                  control: control
              ) else {
            return false
        }
        return profileID.map { publication.profileID == $0 } ?? true
    }

    private func currentPublication(
        for adapter: ExtensionMiniWindowAdapter,
        visibleTo context: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionAuxiliaryWindowPublication? {
        guard let control,
              let session = control.auxiliaryWindowSession(
                  for: adapter.sessionId
              ),
              let publication = ledger.publication(for: session),
              publication.adapter === adapter,
              publication.context === context,
              resolver.publicationIsCurrent(
                  publication,
                  session: session,
                  runtime: runtime,
                  control: control
              ) else {
            return nil
        }
        return publication
    }
}
