import Foundation

/// Owns the external event pair and exact adapter retirement for one captured
/// requested-Tab receipt.
@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabPublicationRetirement {
    private let events: any ExtensionTabLifecycleEventSink
    private let adapters: ExtensionCreatedTabAdapterPublication

    init(
        events: any ExtensionTabLifecycleEventSink,
        adapters: ExtensionCreatedTabAdapterPublication
    ) {
        self.events = events
        self.adapters = adapters
    }

    func emitOpen(_ evidence: ExtensionCreatedTabPublicationEvidence) {
        events.emitDidOpenTab(
            evidence.tab,
            controller: evidence.base.controller,
            adapter: evidence.adapter
        )
    }

    func balanceOpen(
        _ evidence: ExtensionCreatedTabPublicationEvidence,
        adapterStillOpen: Bool
    ) {
        let revoked = evidence.tab.extensionPageRuntimeOwner
            .revokeCommittedWindowPrepublication(
                evidence.stateToken,
                openGeneration: evidence.generation
            )
        if revoked || adapterStillOpen {
            events.emitDidCloseTab(
                evidence.tab,
                controller: evidence.base.controller,
                adapter: evidence.adapter
            )
        }
        adapters.retireExactAdapter(for: evidence)
    }

    func retireAdapter(
        for evidence: ExtensionCreatedTabPublicationEvidence
    ) {
        adapters.retireExactAdapter(for: evidence)
    }
}
