import Foundation
import WebKit

/// Balances the exact initial-Tab event pair and conditionally retires only the
/// adapter created by the same publication evidence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationRetirement {
    private let events: any ExtensionInitialTabLifecycleEventSink
    private let adapters: ExtensionCreatedTabAdapterPublication

    init(
        events: any ExtensionInitialTabLifecycleEventSink,
        adapters: ExtensionCreatedTabAdapterPublication
    ) {
        self.events = events
        self.adapters = adapters
    }

    func emitOpen(_ evidence: ExtensionInitialTabPublicationEvidence) {
        events.emitDidOpenInitialTab(
            evidence.tab,
            controller: evidence.controller,
            adapter: evidence.adapter
        )
    }

    @discardableResult
    func revokeCapturedOpen(
        _ evidence: ExtensionInitialTabPublicationEvidence,
        validator: ExtensionInitialTabPublicationValidator
    ) -> Bool {
        let revoked = evidence.tab.extensionPageRuntimeOwner
            .revokeCommittedWindowPrepublication(
                evidence.stateToken,
                openGeneration: evidence.tabGeneration
            )
        guard revoked else { return false }

        emitCloseAndRetire(
            evidence,
            controller: evidence.controller,
            validator: validator
        )
        return true
    }

    @discardableResult
    func revokeDelegatedOpen(
        _ delegated: ExtensionInitialTabDelegatedOpenEvidence,
        for evidence: ExtensionInitialTabPublicationEvidence,
        validator: ExtensionInitialTabPublicationValidator
    ) -> Bool {
        guard validator.delegatedOpenIsCurrent(delegated, for: evidence),
              evidence.tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    delegated.claim,
                    generation: delegated.generation
                )
        else {
            return false
        }
        emitCloseAndRetire(
            evidence,
            controller: delegated.controller,
            validator: validator
        )
        return true
    }

    private func emitCloseAndRetire(
        _ evidence: ExtensionInitialTabPublicationEvidence,
        controller: WKWebExtensionController,
        validator: ExtensionInitialTabPublicationValidator
    ) {
        events.emitDidCloseInitialTab(
            evidence.tab,
            controller: controller,
            adapter: evidence.adapter
        )
        if validator.createdAdapterCanBeRetired(evidence) {
            adapters.removeCreatedAdapter(
                evidence.adapter,
                for: evidence.tab,
                ifCreated: evidence.createdAdapter
            )
        }
    }

    func removePreparedAdapter(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) {
        adapters.removeCreatedAdapter(
            evidence.adapter,
            for: evidence.tab,
            ifCreated: evidence.createdAdapter
        )
    }
}
