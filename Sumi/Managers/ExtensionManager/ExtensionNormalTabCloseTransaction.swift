import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabCloseReceipt {
    struct Identity: Hashable {
        let tab: ObjectIdentifier
        let adapter: ObjectIdentifier
    }

    let identity: Identity
    let tab: Tab
    let generation: UInt64
    let adapter: ExtensionTabAdapter
    let controller: WKWebExtensionController?
    let openClaim: TabExtensionOpenPublicationClaim?
}

/// Atomically claims one exact did-open generation before crossing WebKit's
/// synchronous close callback, then retires only the adapter that was closed.
/// A nested close sees the tombstone; a same-UUID replacement survives.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabCloseTransaction {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let windowPublications: ExtensionWindowPublicationQuery
    private let events: any ExtensionTabLifecycleEventSink
    private let runtime: @MainActor () -> ExtensionManagerRuntime

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        windowPublications: ExtensionWindowPublicationQuery,
        events: any ExtensionTabLifecycleEventSink,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.windowPublications = windowPublications
        self.events = events
        self.runtime = runtime
    }

    func close(_ tab: Tab) {
        guard let receipt = prepareClose(tab) else { return }
        close(receipt)
    }

    func prepareClose(_ tab: Tab) -> ExtensionNormalTabCloseReceipt? {
        guard windowPublications.isAuxiliarySessionTab(tab) == false,
              let adapter = adapterStore.tabAdapters[tab.id],
              adapter.hasExactTabIdentity(tab)
        else {
            return nil
        }

        let generation = runtimeSession.tabOpenNotificationGeneration
        let controller: WKWebExtensionController?
        let openClaim: TabExtensionOpenPublicationClaim?
        if tab.extensionPageRuntimeOwner.isEligible(for: generation),
           let claim = tab.extensionPageRuntimeOwner
            .currentOpenPublicationClaim(generation: generation),
           let profileID = profileRuntime.resolvedProfileId(
               for: tab,
               runtime: runtime()
           ), let resolvedController = profileRuntime.controller(
               for: profileID
           ) {
            controller = resolvedController
            openClaim = claim
        } else {
            controller = nil
            openClaim = nil
        }
        return ExtensionNormalTabCloseReceipt(
            identity: .init(
                tab: ObjectIdentifier(tab),
                adapter: ObjectIdentifier(adapter)
            ),
            tab: tab,
            generation: generation,
            adapter: adapter,
            controller: controller,
            openClaim: openClaim
        )
    }

    func close(_ receipt: ExtensionNormalTabCloseReceipt) {
        guard adapterStore.tabAdapters[receipt.tab.id]
                === receipt.adapter,
              receipt.adapter.hasExactTabIdentity(receipt.tab)
        else {
            return
        }
        if let controller = receipt.controller,
           let openClaim = receipt.openClaim,
           receipt.tab.extensionPageRuntimeOwner
            .claimDidOpenTabNotificationForClose(
                openClaim,
                generation: receipt.generation
            ) {
            events.emitDidCloseTab(
                receipt.tab,
                controller: controller,
                adapter: receipt.adapter
            )
        }
        _ = adapterStore.removeTabAdapter(
            for: receipt.tab.id,
            ifIdenticalTo: receipt.adapter
        )
    }
}
