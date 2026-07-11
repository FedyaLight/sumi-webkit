import Foundation

/// Phase owner for one captured requested-Tab publication. Exact runtime
/// validation and external event retirement are delegated to narrow concrete
/// collaborators so this receipt cannot grow into another runtime surface.
@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabPublicationReceipt {
    private enum Phase {
        case prepared
        case committed
        case finished
    }

    private let validator: ExtensionCreatedTabPublicationValidator
    private let retirement: ExtensionCreatedTabPublicationRetirement
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let evidence: ExtensionCreatedTabPublicationEvidence
    private var phase = Phase.prepared

    init(
        validator: ExtensionCreatedTabPublicationValidator,
        retirement: ExtensionCreatedTabPublicationRetirement,
        diagnostics: ExtensionRuntimeDiagnostics,
        evidence: ExtensionCreatedTabPublicationEvidence
    ) {
        self.validator = validator
        self.retirement = retirement
        self.diagnostics = diagnostics
        self.evidence = evidence
    }

    @discardableResult
    func commitOpen(runtime: ExtensionManagerRuntime) -> Bool {
        guard phase == .prepared,
              validator.preparedEvidenceIsCurrent(
                  evidence,
                  runtime: runtime
              ), evidence.tab.extensionPageRuntimeOwner
                .commitWindowPrepublication(
                    evidence.stateToken,
                    willEmitOpen: true
                )
        else {
            cancelPreparedIfPossible()
            return false
        }

        evidence.tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration:
                evidence.base.contextBindingGeneration,
            contextReadiness: .loaded
        )
        guard evidence.tab.extensionPageRuntimeOwner.markDidOpenTab(
            generation: evidence.generation,
            committedWindowPrepublication: evidence.stateToken
        ) else {
            _ = evidence.tab.extensionPageRuntimeOwner
                .abortCommittedWindowPrepublicationBeforeOpen(
                    evidence.stateToken
                )
            phase = .finished
            retirement.removeCreatedAdapter(for: evidence)
            return false
        }

        phase = .committed
        retirement.emitOpen(evidence)

        if validator.capturedOpenIsCurrent(evidence, runtime: runtime),
           evidence.tab.extensionPageRuntimeOwner
            .finishCommittedWindowPrepublication(
                evidence.stateToken,
                openGeneration: evidence.generation
            ) {
            finish(reason: "capturedOpen")
            return true
        }

        if validator.currentGenerationOpenIsExact(
            evidence,
            runtime: runtime
        ) {
            finish(reason: "reentrantCurrentOpen")
            return true
        }

        let adapterStillOpen = validator.adapterIsOpenInProfileContexts(
            evidence
        )
        phase = .finished
        retirement.balanceOpen(
            evidence,
            adapterStillOpen: adapterStillOpen
        )
        diagnostics.trace(
            "registerExtensionCreatedTab rejected reason=\(evidence.reason) because=postCallbackStateChanged generation=\(evidence.generation) tab=\(evidence.tab.id.uuidString.prefix(8))"
        )
        return false
    }

    @discardableResult
    func cancel() -> Bool {
        guard phase == .prepared else { return false }
        let restored = evidence.tab.extensionPageRuntimeOwner
            .rollbackWindowPrepublication(evidence.stateToken)
        phase = .finished
        if restored {
            retirement.removeCreatedAdapter(for: evidence)
        }
        return restored
    }

    private func cancelPreparedIfPossible() {
        guard phase == .prepared else { return }
        _ = cancel()
    }

    private func finish(reason completion: String) {
        phase = .finished
        diagnostics.trace(
            "registerExtensionCreatedTab committed reason=\(evidence.reason) because=\(completion) generation=\(evidence.tab.extensionPageRuntimeOwner.currentOpenNotificationGeneration()) tab=\(evidence.tab.id.uuidString.prefix(8))"
        )
    }
}
