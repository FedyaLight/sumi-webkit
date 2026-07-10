//
//  WebViewSessionRepository.swift
//  SumiWebRuntime
//
//  Atomic boundary across active placement and ownership transitions.
//

import Foundation
import WebKit

/// Aggregate transaction boundary. Active placement, transition ownership, and
/// replacement identity state each have one dedicated store; this type keeps
/// only operations that must commit across more than one of them.
@preconcurrency @MainActor
public final class WebViewSessionRepository {
    private let placements: WebViewSessionPlacementStore
    private let transitions: WebViewOwnershipTransitionLedger
    private let replacementTransactions: WebViewReplacementTransactionStore
    private let validator: WebViewSessionConsistencyValidator
    private let replacementCoordinator: WebViewReplacementCoordinator
    public let queries: WebViewSessionQueryService
    package let placement: WebViewSessionPlacementService

    public init() {
        let placements = WebViewSessionPlacementStore()
        let transitions = WebViewOwnershipTransitionLedger()
        let transactions = WebViewReplacementTransactionStore()
        let validator = WebViewSessionConsistencyValidator(
            placements: placements,
            transitions: transitions,
            transactions: transactions
        )
        let queries = WebViewSessionQueryService(
            placements: placements,
            transitions: transitions
        )
        self.placements = placements
        self.transitions = transitions
        replacementTransactions = transactions
        self.validator = validator
        self.queries = queries
        placement = WebViewSessionPlacementService(
            placements: placements,
            transitions: transitions,
            transactions: transactions,
            queries: queries,
            validator: validator
        )
        replacementCoordinator = WebViewReplacementCoordinator(
            placements: placements,
            transitions: transitions,
            transactions: transactions,
            validator: validator
        )
    }

    // MARK: - Reads

    public func snapshot(for tabID: UUID) -> WebViewSessionSnapshot {
        queries.snapshot(for: tabID)
    }

    public var residenceGeneration: UInt64 {
        queries.residenceGeneration
    }

    public func waitUntilOwnershipTransitionsAreSettled() async -> Bool {
        await queries.waitUntilOwnershipTransitionsAreSettled()
    }

    public func residence(of webView: WKWebView) -> WebViewResidence? {
        queries.residence(of: webView)
    }

    public func webView(with identifier: ObjectIdentifier) -> WKWebView? {
        queries.webView(with: identifier)
    }

    public func untrackedWebView(for tabID: UUID) -> WKWebView? {
        queries.untrackedWebView(for: tabID)
    }

    public func parkedWebView(for tabID: UUID) -> WKWebView? {
        queries.parkedWebView(for: tabID)
    }

    public func primaryWindowID(for tabID: UUID) -> UUID? {
        queries.primaryWindowID(for: tabID)
    }

    public var runtimeOwnedTabIDs: Set<UUID> {
        queries.runtimeOwnedTabIDs
    }

    public func protectedCandidateWebViews(for tabID: UUID) -> [WKWebView] {
        queries.runtimeOwnedWebViews(for: tabID)
    }

    // MARK: - Terminal drain

    public func takeAllWebViewsForTerminalShutdown()
        -> [WebViewTerminalCleanupEntry] {
        assertConsistency("takeAllWebViewsForTerminalShutdown.preflight")
        guard placements.hasActiveResidences || transitions.hasTransitions else {
            return []
        }
        let cleanupEntries = placements.drainActiveResidences()
            + transitions.drainTransitions()
        replacementTransactions.removeAll()
        placements.advanceResidenceGeneration()

        let uniqueIDs = Set(cleanupEntries.map { ObjectIdentifier($0.webView) })
        precondition(uniqueIDs.count == cleanupEntries.count)
        let sorted = cleanupEntries.sorted(by: Self.terminalIdentityOrder)
        assertConsistency("takeAllWebViewsForTerminalShutdown.commit")
        return sorted
    }

    // MARK: - Pending cleanup

    public func beginPendingCleanup(
        of webView: WKWebView,
        for tabID: UUID
    ) -> WebViewPendingCleanupLease? {
        if case .pendingCleanup = residence(of: webView) {
            return transitions.claimPendingCleanup(of: webView, for: tabID)
        }
        guard residence(of: webView) == nil else { return nil }
        guard let lease = transitions.claimPendingCleanup(
            of: webView,
            for: tabID
        ) else { return nil }
        placements.advanceResidenceGeneration()
        assertConsistency("beginPendingCleanup")
        return lease
    }

    @discardableResult
    public func consumePendingCleanup(
        of webView: WKWebView,
        lease: WebViewPendingCleanupLease
    ) -> Bool {
        guard residence(of: webView) == .pendingCleanup(lease),
              transitions.consumePendingCleanup(
                of: webView,
                lease: lease
              ) else { return false }
        placements.advanceResidenceGeneration()
        assertConsistency("consumePendingCleanup")
        return true
    }

    public func releaseUntrackedAndBeginPendingCleanup(
        _ expectedCurrent: WKWebView,
        for tabID: UUID
    ) -> WebViewPendingCleanupLease? {
        transitionDetachedToPendingCleanup(
            expectedCurrent,
            expectedResidence: .untracked(tabID: tabID),
            replacement: nil,
            for: tabID
        )
    }

    public func releaseParkedAndBeginPendingCleanup(
        _ expectedCurrent: WKWebView,
        for tabID: UUID
    ) -> WebViewPendingCleanupLease? {
        transitionDetachedToPendingCleanup(
            expectedCurrent,
            expectedResidence: .parked(tabID: tabID),
            replacement: nil,
            for: tabID
        )
    }

    public func replaceDetachedSetAndBeginPendingCleanup(
        with replacement: WKWebView,
        residence replacementResidence: WebViewDetachedReplacementResidence,
        expectedGeneration: UInt64,
        for tabID: UUID
    ) -> WebViewDetachedSetReplacementResult {
        guard !replacementTransactions.containsTransaction(for: tabID) else {
            return .invalid
        }
        let currentGeneration = queries.generation(for: tabID)
        guard currentGeneration == expectedGeneration else {
            return .stale(currentGeneration: currentGeneration)
        }
        guard var entry = placements.entry(for: tabID),
              entry.windowWebViews.isEmpty,
              entry.parkedWebView != nil || entry.untrackedWebView != nil,
              residence(of: replacement) == nil else {
            return .invalid
        }

        let displaced = uniqueWebViews(
            [entry.parkedWebView, entry.untrackedWebView].compactMap(\.self)
        )
        placements.removeResidence(
            for: entry.parkedWebView,
            expected: .parked(tabID: tabID)
        )
        placements.removeResidence(
            for: entry.untrackedWebView,
            expected: .untracked(tabID: tabID)
        )
        entry.parkedWebView = nil
        entry.untrackedWebView = nil
        switch replacementResidence {
        case .parked:
            entry.parkedWebView = replacement
        case .untracked:
            entry.untrackedWebView = replacement
        }
        placements.storeMutated(entry, for: tabID)
        placements.installActiveResidences(in: entry, tabID: tabID)

        let claims = displaced.map { webView in
            guard let lease = transitions.claimPendingCleanup(
                of: webView,
                for: tabID
            ) else {
                preconditionFailure("Displaced detached WebView lost cleanup")
            }
            return WebViewPendingCleanupClaim(webView: webView, lease: lease)
        }
        assertConsistency("replaceDetachedSetAndBeginPendingCleanup")
        return .committed(displaced: claims)
    }

    // MARK: - Detached placement

    public func noteParkedWebView(_ webView: WKWebView?, for tabID: UUID) {
        placement.noteParkedWebView(webView, for: tabID)
    }

    public func noteUntrackedWebView(_ webView: WKWebView?, for tabID: UUID) {
        placement.noteUntrackedWebView(webView, for: tabID)
    }

    public func adoptParkedWebViewAsUntracked(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        placement.adoptParkedWebViewAsUntracked(
            webView,
            for: tabID
        )
    }

    @discardableResult
    public func removeDetachedWebView(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        placement.removeDetachedWebView(webView, for: tabID)
    }

    // MARK: - Window reads

    public var isTrackingEmpty: Bool { queries.isTrackingEmpty }
    public var totalTrackedWebViewCount: Int {
        queries.totalTrackedWebViewCount
    }

    public func webView(for tabID: UUID, in windowID: UUID) -> WKWebView? {
        queries.webView(for: tabID, in: windowID)
    }

    public func webViews(for tabID: UUID) -> [WKWebView] {
        queries.webViews(for: tabID)
    }

    public func windowWebViews(for tabID: UUID) -> [UUID: WKWebView] {
        queries.windowWebViews(for: tabID)
    }

    public func windowIDs(for tabID: UUID) -> [UUID] {
        queries.windowIDs(for: tabID)
    }

    public func trackedWebViews(
        in windowID: UUID
    ) -> [(TrackedWebViewOwner, WKWebView)] {
        queries.trackedWebViews(in: windowID)
    }

    public func trackedOwner(
        with identifier: ObjectIdentifier
    ) -> TrackedWebViewOwner? {
        queries.trackedOwner(with: identifier)
    }

    public func isIndexed(_ webView: WKWebView) -> Bool {
        queries.isIndexed(webView)
    }

    public func trackedOwner(
        containing webView: WKWebView
    ) -> TrackedWebViewOwner? {
        trackedOwner(with: ObjectIdentifier(webView))
    }

    // MARK: - Transactional replacement

    @preconcurrency
    public func beginReplacementBatch(
        _ replacementEntries: [WebViewReplacementBatchEntry],
        validateModel: @MainActor () -> Bool = { return true },
        modelCommit: @MainActor () throws -> Void = { () }
    ) -> WebViewReplacementBatchBeginResult {
        replacementCoordinator.begin(
            replacementEntries,
            validateModel: validateModel,
            modelCommit: modelCommit
        )
    }

    public func beginWindowSetReplacement(
        for tabID: UUID,
        expectedGeneration: UInt64,
        webViewsByWindowID: [UUID: WKWebView],
        primaryWindowID: UUID
    ) -> WebViewReplacementBatchBeginResult {
        beginReplacementBatch([
            WebViewReplacementBatchEntry(
                tabID: tabID,
                expectedGeneration: expectedGeneration,
                placement: .windowSet(
                    webViewsByWindowID: webViewsByWindowID,
                    primaryWindowID: primaryWindowID
                )
            ),
        ])
    }

    public func beginDetachedSetReplacement(
        with replacement: WKWebView,
        residence: WebViewDetachedReplacementResidence,
        expectedGeneration: UInt64,
        for tabID: UUID
    ) -> WebViewReplacementBatchBeginResult {
        beginReplacementBatch([
            WebViewReplacementBatchEntry(
                tabID: tabID,
                expectedGeneration: expectedGeneration,
                placement: .detached(
                    webView: replacement,
                    residence: residence
                )
            ),
        ])
    }

    public func commitReplacementBatch(
        _ lease: WebViewReplacementBatchLease
    ) -> WebViewReplacementBatchCommitResult {
        replacementCoordinator.commit(lease)
    }

    @preconcurrency
    public func rollbackReplacementBatch(
        _ lease: WebViewReplacementBatchLease,
        modelRollback: @MainActor () throws -> Void = { () }
    ) -> WebViewReplacementBatchRollbackResult {
        replacementCoordinator.rollback(
            lease,
            modelRollback: modelRollback
        )
    }

    // MARK: - Invariants

    public func assertConsistency(_ context: StaticString) {
        validator.assertConsistency(context)
    }

    // MARK: - Cross-store mutation helpers

    private func transitionDetachedToPendingCleanup(
        _ expectedCurrent: WKWebView,
        expectedResidence: WebViewResidence,
        replacement: WKWebView?,
        for tabID: UUID
    ) -> WebViewPendingCleanupLease? {
        guard !replacementTransactions.containsTransaction(for: tabID),
              var entry = placements.entry(for: tabID),
              expectedResidence.tabID == tabID,
              entry.windowWebViews.isEmpty,
              residence(of: expectedCurrent) == expectedResidence,
              replacement !== expectedCurrent else { return nil }

        switch expectedResidence {
        case .parked:
            guard entry.parkedWebView === expectedCurrent,
                  replacement == nil else { return nil }
            entry.parkedWebView = nil
        case .untracked:
            guard entry.untrackedWebView === expectedCurrent else { return nil }
            entry.untrackedWebView = replacement
        case .window, .retiring, .pendingCleanup:
            return nil
        }
        if let replacement, residence(of: replacement) != nil { return nil }

        placements.removeResidence(
            for: expectedCurrent,
            expected: expectedResidence
        )
        placements.storeMutated(entry, for: tabID)
        placements.installActiveResidences(in: entry, tabID: tabID)
        guard let lease = transitions.claimPendingCleanup(
            of: expectedCurrent,
            for: tabID
        ) else {
            preconditionFailure("Detached WebView lost cleanup transition")
        }
        assertConsistency("transitionDetachedToPendingCleanup")
        return lease
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        return webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    private static func terminalIdentityOrder(
        _ lhs: WebViewTerminalCleanupEntry,
        _ rhs: WebViewTerminalCleanupEntry
    ) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs.webView))
            < UInt(bitPattern: ObjectIdentifier(rhs.webView))
    }
}
