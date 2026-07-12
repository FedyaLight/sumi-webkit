import Foundation
import WebKit

/// Single-use phase machine for one immutable initial-Tab evidence capture.
/// Runtime validation, callbacks, and adapter retirement remain in narrow
/// collaborators; the receipt stores no ExtensionManager root.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationReceipt:
    InitialTabExtensionPublication {
    private enum Phase {
        case prepared
        case publishedByReceipt
        case delegatedToCurrentGeneration(
            ExtensionInitialTabDelegatedOpenEvidence
        )
        case finished
    }

    private let validator: ExtensionInitialTabPublicationValidator
    private let retirement: ExtensionInitialTabPublicationRetirement
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let evidence: ExtensionInitialTabPublicationEvidence
    private var phase = Phase.prepared

    init(
        validator: ExtensionInitialTabPublicationValidator,
        retirement: ExtensionInitialTabPublicationRetirement,
        diagnostics: ExtensionRuntimeDiagnostics,
        evidence: ExtensionInitialTabPublicationEvidence
    ) {
        self.validator = validator
        self.retirement = retirement
        self.diagnostics = diagnostics
        self.evidence = evidence
    }

    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        isPrepared
            && evidence.window === window
            && evidence.tab === tab
            && evidence.webView === webView
    }

    func validateBeforeWindowPublication() -> Bool {
        isPrepared
            && validator.preparedEvidenceIsCurrent(
                evidence,
                requiresPublishedWindow: false
            )
    }

    @discardableResult
    func publishInitialTab(
        afterWindowOpened window: BrowserWindowState
    ) -> Bool {
        guard case .prepared = phase, evidence.window === window else {
            return false
        }

        // didOpenWindow may synchronously complete ordinary Tab registration.
        // That newer exact publisher invalidates this prepared token and owns
        // the open; retain only the evidence needed to balance a later native
        // registration rollback.
        if let delegated = validator.currentGenerationOpenEvidence(evidence) {
            return acceptDelegatedOpen(delegated)
        }

        guard validator.preparedEvidenceIsCurrent(
            evidence,
            requiresPublishedWindow: true
        ), evidence.tab.extensionPageRuntimeOwner
            .hasDidOpenTabNotification(for: evidence.tabGeneration) == false
        else {
            return false
        }

        guard evidence.tab.extensionPageRuntimeOwner
            .commitWindowPrepublication(
                evidence.stateToken,
                willEmitOpen: true
            )
        else {
            return false
        }

        evidence.tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration:
                evidence.contextBindingGeneration,
            contextReadiness: .loaded
        )
        guard let openClaim = evidence.tab.extensionPageRuntimeOwner
            .reserveDidOpenTab(
                generation: evidence.tabGeneration,
                committedWindowPrepublication: evidence.stateToken
            ) else {
            _ = evidence.tab.extensionPageRuntimeOwner
                .abortCommittedWindowPrepublicationBeforeOpen(
                    evidence.stateToken
                )
            phase = .finished
            retirement.removePreparedAdapter(evidence)
            return false
        }

        // Reserve the open before entering WebKit. Nested teardown now sees a
        // committed claim and cannot emit a duplicate open.
        phase = .publishedByReceipt
        retirement.emitOpen(evidence)

        if validator.capturedOpenIsCurrent(evidence),
           evidence.tab.extensionPageRuntimeOwner
            .settleDidOpenTabNotification(
                openClaim,
                generation: evidence.tabGeneration
            ) {
            diagnostics.trace(
                "initialTabWindowPublication committed reason=\(evidence.reason) generation=\(evidence.tabGeneration) tab=\(evidence.tab.id.uuidString.prefix(8)) window=\(evidence.window.id.uuidString.prefix(8))"
            )
            return true
        }
        if let delegated = validator.currentGenerationOpenEvidence(evidence) {
            return acceptDelegatedOpen(delegated)
        }

        // Tombstone before the balancing callback so reentrant retirement is
        // idempotent and cannot close this captured event twice.
        phase = .finished
        _ = retirement.revokeCapturedOpen(
            evidence,
            validator: validator
        )
        diagnostics.trace(
            "initialTabWindowPublication rejected reason=\(evidence.reason) because=postCallbackStateChanged generation=\(evidence.tabGeneration) tab=\(evidence.tab.id.uuidString.prefix(8)) window=\(evidence.window.id.uuidString.prefix(8))"
        )
        return false
    }

    @discardableResult
    func cancel() -> Bool {
        guard case .prepared = phase else { return false }
        let restored = evidence.tab.extensionPageRuntimeOwner
            .rollbackWindowPrepublication(evidence.stateToken)
        phase = .finished
        if restored {
            retirement.removePreparedAdapter(evidence)
        }
        return restored
    }

    @discardableResult
    func revokePublishedIfCurrent() -> Bool {
        if case .delegatedToCurrentGeneration(let delegated) = phase {
            phase = .finished
            return retirement.revokeDelegatedOpen(
                delegated,
                for: evidence,
                validator: validator
            )
        }
        guard case .publishedByReceipt = phase else { return false }
        phase = .finished
        let revoked = retirement.revokeCapturedOpen(
            evidence,
            validator: validator
        )
        if revoked {
            diagnostics.trace(
                "initialTabWindowPublication revoked reason=\(evidence.reason) generation=\(evidence.tabGeneration) tab=\(evidence.tab.id.uuidString.prefix(8)) window=\(evidence.window.id.uuidString.prefix(8))"
            )
        }
        return revoked
    }

    private var isPrepared: Bool {
        if case .prepared = phase { return true }
        return false
    }

    private func acceptDelegatedOpen(
        _ delegated: ExtensionInitialTabDelegatedOpenEvidence
    ) -> Bool {
        guard evidence.tab.extensionPageRuntimeOwner
            .finishWindowPrepublicationForDelegatedOpen(
                evidence.stateToken,
                claim: delegated.claim
            )
        else {
            return false
        }
        phase = .delegatedToCurrentGeneration(delegated)
        return true
    }
}
