import Foundation
import WebKit

/// Narrow command surface for active placement. Transaction and transition
/// guards are enforced here before the canonical placement store is mutated.
@MainActor
package final class WebViewSessionPlacementService {
    private unowned let placements: WebViewSessionPlacementStore
    private unowned let transitions: WebViewOwnershipTransitionLedger
    private unowned let transactions: WebViewSessionTransitionTransactionStore
    private unowned let queries: WebViewSessionQueryService
    private unowned let validator: WebViewSessionConsistencyValidator

    init(
        placements: WebViewSessionPlacementStore,
        transitions: WebViewOwnershipTransitionLedger,
        transactions: WebViewSessionTransitionTransactionStore,
        queries: WebViewSessionQueryService,
        validator: WebViewSessionConsistencyValidator
    ) {
        self.placements = placements
        self.transitions = transitions
        self.transactions = transactions
        self.queries = queries
        self.validator = validator
    }

    func noteParkedWebView(_ webView: WKWebView?, for tabID: UUID) {
        guard !transactions.containsTransaction(for: tabID) else { return }
        requireNoTransitionResidence(webView)
        placements.noteParkedWebView(webView, for: tabID)
        validator.assertConsistency("placement.noteParkedWebView")
    }

    func noteUntrackedWebView(_ webView: WKWebView?, for tabID: UUID) {
        guard !transactions.containsTransaction(for: tabID) else { return }
        requireNoTransitionResidence(webView)
        placements.noteUntrackedWebView(webView, for: tabID)
        validator.assertConsistency("placement.noteUntrackedWebView")
    }

    func adoptParkedWebViewAsUntracked(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        guard !transactions.containsTransaction(for: tabID) else {
            return false
        }
        let adopted = placements.adoptParkedWebViewAsUntracked(
            webView,
            for: tabID
        )
        if adopted {
            validator.assertConsistency("placement.adoptParkedAsUntracked")
        }
        return adopted
    }

    func clearDetachedWebViews(for tabID: UUID) {
        guard !transactions.containsTransaction(for: tabID) else { return }
        placements.clearDetachedWebViews(for: tabID)
        validator.assertConsistency("placement.clearDetachedWebViews")
    }

    func removeDetachedWebView(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        guard !transactions.containsTransaction(for: tabID) else {
            return false
        }
        let removed = placements.removeDetachedWebView(webView, for: tabID)
        if removed {
            validator.assertConsistency("placement.removeDetachedWebView")
        }
        return removed
    }

    package func promoteTrackedWebViewToPrimary(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView
    ) -> Bool {
        guard !transactions.containsTransaction(for: owner.tabID) else {
            return false
        }
        let promoted = placements.promoteTrackedWebViewToPrimary(
            owner: owner,
            expectedWebView: expectedWebView
        )
        if promoted {
            validator.assertConsistency("placement.promoteTrackedPrimary")
        }
        return promoted
    }

    package func registerWindowWebView(
        _ webView: WKWebView,
        for owner: TrackedWebViewOwner,
        canDisplaceWebView: (WKWebView) -> Bool
    ) -> WebViewWindowSlotRegistrationResult {
        guard !transactions.containsTransaction(for: owner.tabID) else {
            return .rejected(.changedDuringPreflight)
        }
        let initialGeneration = queries.generation(for: owner.tabID)
        let candidateResidence = queries.residence(of: webView)

        if let candidateResidence {
            guard candidateResidence.tabID == owner.tabID else {
                return .rejected(.crossTabCandidate)
            }
            if case .pendingCleanup = candidateResidence {
                return .rejected(.pendingCleanupCandidate)
            }
            guard queries.webView(with: ObjectIdentifier(webView)) === webView
            else {
                return .rejected(.inconsistentIdentity)
            }
        }

        let trackedOccupant = queries.webView(for: owner)
        if let trackedOccupant,
           queries.residence(of: trackedOccupant) != .window(owner) {
            return .rejected(.inconsistentIdentity)
        }
        let untrackedOccupant = queries.untrackedWebView(for: owner.tabID)
        if let untrackedOccupant,
           queries.residence(of: untrackedOccupant)
            != .untracked(tabID: owner.tabID) {
            return .rejected(.inconsistentIdentity)
        }
        if trackedOccupant === webView { return .unchanged }

        guard canDisplaceWebView(webView) else {
            return .rejected(.protectedCandidate)
        }
        if let trackedOccupant, trackedOccupant !== webView,
           !canDisplaceWebView(trackedOccupant) {
            return .rejected(.protectedTrackedOccupant)
        }
        if let untrackedOccupant, untrackedOccupant !== webView,
           !canDisplaceWebView(untrackedOccupant) {
            return .rejected(.protectedUntrackedOccupant)
        }

        guard !transactions.containsTransaction(for: owner.tabID),
              queries.generation(for: owner.tabID) == initialGeneration,
              queries.residence(of: webView) == candidateResidence,
              queries.webView(for: owner) === trackedOccupant,
              queries.untrackedWebView(for: owner.tabID) === untrackedOccupant,
              !isTransitionResidence(candidateResidence) else {
            return .rejected(.changedDuringPreflight)
        }

        let commit = placements.commitWindowRegistration(
            webView,
            for: owner,
            candidateResidence: candidateResidence,
            trackedOccupant: trackedOccupant,
            untrackedOccupant: untrackedOccupant
        )
        validator.assertConsistency("placement.registerWindowWebView")
        return .committed(commit)
    }

    package func removeWindowWebView(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView?
    ) -> WKWebView? {
        guard !transactions.containsTransaction(for: owner.tabID) else {
            return nil
        }
        let removed = placements.removeWindowWebView(
            owner: owner,
            expectedWebView: expectedWebView
        )
        if removed != nil {
            validator.assertConsistency("placement.removeWindowWebView")
        }
        return removed
    }

    package func replaceWindowSet(
        for tabID: UUID,
        expectedGeneration: UInt64,
        webViewsByWindowID: [UUID: WKWebView],
        primaryWindowID: UUID
    ) -> WebViewWindowSetReplacementResult {
        guard !transactions.containsTransaction(for: tabID),
              webViewsByWindowID.values.allSatisfy({
                queries.residence(of: $0) == nil
              }) else { return .invalid }
        let result = placements.replaceWindowSet(
            for: tabID,
            expectedGeneration: expectedGeneration,
            webViewsByWindowID: webViewsByWindowID,
            primaryWindowID: primaryWindowID
        )
        if case .committed = result {
            validator.assertConsistency("placement.replaceWindowSet")
        }
        return result
    }

    package func clearAll(for tabID: UUID) {
        guard !transactions.containsTransaction(for: tabID) else { return }
        placements.clearAll(for: tabID)
        validator.assertConsistency("placement.clearAll")
    }

    private func requireNoTransitionResidence(_ webView: WKWebView?) {
        guard let webView else { return }
        switch transitions.residence(of: webView) {
        case .retiring:
            preconditionFailure(
                "A retiring WebView cannot return to active placement"
            )
        case .pendingCleanup:
            preconditionFailure(
                "A cleanup-leased WebView cannot return to active placement"
            )
        case .parked, .untracked, .window:
            preconditionFailure("Transition ledger contains active residence")
        case nil:
            break
        }
    }

    private func isTransitionResidence(
        _ residence: WebViewResidence?
    ) -> Bool {
        switch residence {
        case .retiring, .pendingCleanup:
            return true
        case .parked, .untracked, .window, nil:
            return false
        }
    }
}
