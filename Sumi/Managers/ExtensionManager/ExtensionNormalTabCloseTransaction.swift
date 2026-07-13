import Foundation
import WebKit

/// Atomically claims one exact did-open generation before crossing WebKit's
/// synchronous close callback, then retires only the adapter that was closed.
/// A nested close sees the tombstone; a same-UUID replacement survives.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabCloseTransaction {
    private struct InFlightClose: Hashable {
        let tab: ObjectIdentifier
        let adapter: ObjectIdentifier
        let controller: ObjectIdentifier
    }

    private let tabPublicationRevisions:
        ExtensionTabPublicationRevisionAuthority
    private let adapterStore: ExtensionBrowserAdapterStore
    private let windowPublications: ExtensionWindowPublicationQuery
    private let preparedTabVisibility: ExtensionPreparedTabVisibility
    private let events: any ExtensionTabLifecycleEventSink
    private var inFlightCloses: Set<InFlightClose> = []

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        adapterStore: ExtensionBrowserAdapterStore,
        windowPublications: ExtensionWindowPublicationQuery,
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        events: any ExtensionTabLifecycleEventSink
    ) {
        self.tabPublicationRevisions = tabPublicationRevisions
        self.adapterStore = adapterStore
        self.windowPublications = windowPublications
        self.preparedTabVisibility = preparedTabVisibility
        self.events = events
    }

    func close(_ tab: Tab) {
        guard let receipt = prepareClose(tab) else { return }
        close(receipt)
    }

    func prepareClose(_ tab: Tab) -> ExtensionNormalTabCloseReceipt? {
        guard windowPublications.isAuxiliarySessionTab(tab) == false else {
            return nil
        }
        tab.extensionPageRuntimeOwner.retireFutureOpenPublications()

        let generation = tabPublicationRevisions.issue()
        let openClaim = tab.extensionPageRuntimeOwner.isEligible(for: generation)
            ? tab.extensionPageRuntimeOwner
                .currentOpenPublicationClaim(generation: generation)
            : nil
        let storedAdapter = adapterStore.tabAdapters[tab.id].flatMap {
            $0.hasExactTabIdentity(tab) ? $0 : nil
        }
        let published = openClaim.flatMap { claim in
            publishedTarget(for: tab, claim: claim)
        }
        let implicit = storedAdapter.flatMap { adapter in
            preparedTabVisibility.controllerExposingPreparedAdapter(adapter)
                .map {
                    ExtensionNormalTabCloseReceipt.Publication(
                        controller: $0,
                        adapter: adapter
                    )
                }
        }
        guard openClaim != nil || implicit != nil || storedAdapter != nil else {
            return nil
        }
        return ExtensionNormalTabCloseReceipt(
            tab: tab,
            generation: generation,
            storedAdapter: storedAdapter,
            published: published,
            implicit: implicit,
            openClaim: openClaim
        )
    }

    func close(_ receipt: ExtensionNormalTabCloseReceipt) {
        guard receipt.beginClose() else { return }

        var publications: [ExtensionNormalTabCloseReceipt.Publication] = []
        if let openClaim = receipt.openClaim {
            let claimed = receipt.tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    openClaim,
                    generation: receipt.generation
                )
            if claimed, let published = receipt.published {
                publications.append(published)
            }
        }
        if let implicit = receipt.implicit,
           controllerContains(
               implicit.adapter,
               controller: implicit.controller
           ), publications.contains(where: {
               $0.controller === implicit.controller
                   && $0.adapter === implicit.adapter
           }) == false {
            publications.append(implicit)
        }
        for publication in publications {
            emitClose(
                tab: receipt.tab,
                adapter: publication.adapter,
                controller: publication.controller
            )
        }
        if let storedAdapter = receipt.storedAdapter {
            _ = adapterStore.removeTabAdapter(
                for: receipt.tab.id,
                ifIdenticalTo: storedAdapter
            )
        }
    }

    private func publishedTarget(
        for tab: Tab,
        claim: TabExtensionOpenPublicationClaim
    ) -> ExtensionNormalTabCloseReceipt.Publication? {
        guard let authority = claim.publicationAuthority(),
              let controller = authority.publisher
                  as? WKWebExtensionController,
              let adapter = authority.adapter as? ExtensionTabAdapter,
              adapter.hasExactTabIdentity(tab),
              claim.representsPublication(
                  publisher: controller,
                  adapter: adapter
              )
        else { return nil }
        return ExtensionNormalTabCloseReceipt.Publication(
            controller: controller,
            adapter: adapter
        )
    }

    private func controllerContains(
        _ adapter: ExtensionTabAdapter,
        controller: WKWebExtensionController
    ) -> Bool {
        controller.extensionContexts.contains { context in
            context.openTabs.contains { ($0 as AnyObject) === adapter }
        }
    }

    private func emitClose(
        tab: Tab,
        adapter: ExtensionTabAdapter,
        controller: WKWebExtensionController
    ) {
        let claim = InFlightClose(
            tab: ObjectIdentifier(tab),
            adapter: ObjectIdentifier(adapter),
            controller: ObjectIdentifier(controller)
        )
        guard inFlightCloses.insert(claim).inserted else { return }
        defer { inFlightCloses.remove(claim) }
        events.emitDidCloseTab(
            tab,
            controller: controller,
            adapter: adapter
        )
    }
}
