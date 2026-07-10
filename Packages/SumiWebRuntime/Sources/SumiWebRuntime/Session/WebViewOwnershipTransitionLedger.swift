import Foundation
import WebKit

/// Sole strong owner for WebViews that are between active placement and
/// physical destruction/restoration. Pending cleanup owns individual views;
/// retirement owns one complete previous-generation snapshot per tab.
@MainActor
final class WebViewOwnershipTransitionLedger {
    private struct PendingCleanupEntry {
        let lease: WebViewPendingCleanupLease
        let webView: WKWebView
    }

    private var pendingCleanupByWebViewID: [
        ObjectIdentifier: PendingCleanupEntry
    ] = [:]
    private var retirementSnapshotsByLease: [
        WebViewRetirementLease: WebViewSessionSnapshot
    ] = [:]
    private var retirementLeaseByWebViewID: [
        ObjectIdentifier: WebViewRetirementLease
    ] = [:]
    private var openReplacementBatchIDs: Set<UUID> = []
    private var pendingCleanupWaiters: [
        UUID: CheckedContinuation<Bool, Never>
    ] = [:]
    private var ownershipTransitionWaiters: [
        UUID: CheckedContinuation<Bool, Never>
    ] = [:]

    var pendingCleanupTabIDs: Set<UUID> {
        Set(pendingCleanupByWebViewID.values.map(\.lease.tabID))
    }

    var retirementTabIDs: Set<UUID> {
        Set(retirementSnapshotsByLease.keys.map(\.tabID))
    }

    var openBatchIDs: Set<UUID> { openReplacementBatchIDs }
    var hasTransitions: Bool {
        !pendingCleanupByWebViewID.isEmpty
            || !retirementSnapshotsByLease.isEmpty
            || !openReplacementBatchIDs.isEmpty
    }

    var transitionResidences: [ObjectIdentifier: WebViewResidence] {
        var residences = pendingCleanupByWebViewID.mapValues {
            WebViewResidence.pendingCleanup($0.lease)
        }
        for (webViewID, lease) in retirementLeaseByWebViewID {
            residences[webViewID] = .retiring(lease)
        }
        return residences
    }

    func residence(of webView: WKWebView) -> WebViewResidence? {
        residence(with: ObjectIdentifier(webView))
    }

    func residence(with identifier: ObjectIdentifier) -> WebViewResidence? {
        if let pending = pendingCleanupByWebViewID[identifier] {
            return .pendingCleanup(pending.lease)
        }
        if let lease = retirementLeaseByWebViewID[identifier] {
            return .retiring(lease)
        }
        return nil
    }

    func webView(with identifier: ObjectIdentifier) -> WKWebView? {
        if let pending = pendingCleanupByWebViewID[identifier] {
            guard ObjectIdentifier(pending.webView) == identifier else {
                assertionFailure("Pending-cleanup identity diverged")
                return nil
            }
            return pending.webView
        }
        guard let lease = retirementLeaseByWebViewID[identifier],
              let snapshot = retirementSnapshotsByLease[lease] else {
            return nil
        }
        let webView = snapshot.allKnownWebViews.first {
            ObjectIdentifier($0) == identifier
        }
        if webView == nil {
            assertionFailure("Retirement identity diverged")
        }
        return webView
    }

    func pendingCleanupSnapshot(
        generation: UInt64
    ) -> WebViewPendingCleanupSnapshot {
        let entries = pendingCleanupByWebViewID.values
            .map {
                WebViewPendingCleanupEntry(
                    lease: $0.lease,
                    webView: $0.webView
                )
            }
            .sorted(by: Self.webViewIdentityOrder)
        return WebViewPendingCleanupSnapshot(
            generation: generation,
            entries: entries
        )
    }

    func ownershipTransitionSnapshot(
        generation: UInt64
    ) -> WebViewOwnershipTransitionSnapshot {
        let pending = pendingCleanupByWebViewID.values
            .map {
                WebViewPendingCleanupEntry(
                    lease: $0.lease,
                    webView: $0.webView
                )
            }
            .sorted(by: Self.webViewIdentityOrder)
        var retirement: [WebViewRetirementEntry] = []
        for (lease, snapshot) in retirementSnapshotsByLease {
            retirement.append(
                contentsOf: snapshot.allKnownWebViews.map {
                    WebViewRetirementEntry(lease: lease, webView: $0)
                }
            )
        }
        return WebViewOwnershipTransitionSnapshot(
            generation: generation,
            pendingCleanupEntries: pending,
            retirementEntries: retirement.sorted(by: Self.webViewIdentityOrder)
        )
    }

    func waitUntilPendingCleanupIsEmpty() async -> Bool {
        guard !pendingCleanupByWebViewID.isEmpty else { return true }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if pendingCleanupByWebViewID.isEmpty {
                    continuation.resume(returning: true)
                } else {
                    pendingCleanupWaiters[waiterID] = continuation
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumePendingCleanupWaiter(
                    waiterID,
                    returning: false
                )
            }
        }
    }

    func waitUntilSettled() async -> Bool {
        guard hasTransitions else { return true }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if !hasTransitions {
                    continuation.resume(returning: true)
                } else {
                    ownershipTransitionWaiters[waiterID] = continuation
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumeOwnershipTransitionWaiter(
                    waiterID,
                    returning: false
                )
            }
        }
    }

    func claimPendingCleanup(
        of webView: WKWebView,
        for tabID: UUID
    ) -> WebViewPendingCleanupLease? {
        let webViewID = ObjectIdentifier(webView)
        if let existing = pendingCleanupByWebViewID[webViewID] {
            guard existing.webView === webView,
                  existing.lease.tabID == tabID else { return nil }
            return existing.lease
        }
        guard retirementLeaseByWebViewID[webViewID] == nil else { return nil }
        let lease = WebViewPendingCleanupLease(id: UUID(), tabID: tabID)
        pendingCleanupByWebViewID[webViewID] = PendingCleanupEntry(
            lease: lease,
            webView: webView
        )
        return lease
    }

    func consumePendingCleanup(
        of webView: WKWebView,
        lease: WebViewPendingCleanupLease
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let pending = pendingCleanupByWebViewID[webViewID],
              pending.webView === webView,
              pending.lease == lease else { return false }
        pendingCleanupByWebViewID.removeValue(forKey: webViewID)
        resumePendingCleanupWaitersIfPossible()
        resumeOwnershipTransitionWaitersIfPossible()
        return true
    }

    func openReplacementBatch(_ batchID: UUID) {
        precondition(openReplacementBatchIDs.insert(batchID).inserted)
    }

    func retainRetirement(
        _ snapshot: WebViewSessionSnapshot,
        lease: WebViewRetirementLease
    ) {
        precondition(openReplacementBatchIDs.contains(lease.batchID))
        precondition(retirementSnapshotsByLease[lease] == nil)
        for webView in snapshot.allKnownWebViews {
            let webViewID = ObjectIdentifier(webView)
            precondition(pendingCleanupByWebViewID[webViewID] == nil)
            precondition(retirementLeaseByWebViewID[webViewID] == nil)
            retirementLeaseByWebViewID[webViewID] = lease
        }
        retirementSnapshotsByLease[lease] = snapshot
    }

    func retirementSnapshot(
        for lease: WebViewRetirementLease
    ) -> WebViewSessionSnapshot? {
        retirementSnapshotsByLease[lease]
    }

    func retirementIsIntact(_ lease: WebViewRetirementLease) -> Bool {
        guard let snapshot = retirementSnapshotsByLease[lease] else {
            return false
        }
        return snapshot.allKnownWebViews.allSatisfy { webView in
            retirementLeaseByWebViewID[ObjectIdentifier(webView)] == lease
        }
    }

    func retirementWebViews(for tabID: UUID) -> [WKWebView] {
        retirementSnapshotsByLease.compactMap { lease, snapshot in
            lease.tabID == tabID ? snapshot.allKnownWebViews : nil
        }.flatMap(\.self)
    }

    func takeRetirement(
        _ lease: WebViewRetirementLease
    ) -> WebViewSessionSnapshot? {
        guard let snapshot = retirementSnapshotsByLease.removeValue(
            forKey: lease
        ) else { return nil }
        for webView in snapshot.allKnownWebViews {
            let webViewID = ObjectIdentifier(webView)
            if retirementLeaseByWebViewID[webViewID] == lease {
                retirementLeaseByWebViewID.removeValue(forKey: webViewID)
            }
        }
        resumeOwnershipTransitionWaitersIfPossible()
        return snapshot
    }

    func finishReplacementBatch(_ batchID: UUID) {
        precondition(
            retirementSnapshotsByLease.keys.map(\.batchID).contains(batchID)
                == false,
            "Replacement batch finished while retirement remained"
        )
        openReplacementBatchIDs.remove(batchID)
        resumeOwnershipTransitionWaitersIfPossible()
    }

    func drainTransitions() -> [WebViewTerminalCleanupEntry] {
        var cleanupEntries = pendingCleanupByWebViewID.values.map {
            WebViewTerminalCleanupEntry(
                webView: $0.webView,
                residence: .pendingCleanup($0.lease)
            )
        }
        for (lease, snapshot) in retirementSnapshotsByLease {
            cleanupEntries.append(
                contentsOf: snapshot.allKnownWebViews.map {
                    WebViewTerminalCleanupEntry(
                        webView: $0,
                        residence: .retiring(lease)
                    )
                }
            )
        }
        pendingCleanupByWebViewID.removeAll()
        retirementSnapshotsByLease.removeAll()
        retirementLeaseByWebViewID.removeAll()
        openReplacementBatchIDs.removeAll()
        resumeAllPendingCleanupWaiters(returning: false)
        resumeAllOwnershipTransitionWaiters(returning: false)
        return cleanupEntries
    }

    func assertConsistency(_ context: StaticString) {
        #if DEBUG
            var expectedRetirementIndex: [
                ObjectIdentifier: WebViewRetirementLease
            ] = [:]
            for (webViewID, pending) in pendingCleanupByWebViewID {
                assert(ObjectIdentifier(pending.webView) == webViewID)
                assert(retirementLeaseByWebViewID[webViewID] == nil)
            }
            for (lease, snapshot) in retirementSnapshotsByLease {
                assert(openReplacementBatchIDs.contains(lease.batchID))
                for webView in snapshot.allKnownWebViews {
                    let webViewID = ObjectIdentifier(webView)
                    assert(expectedRetirementIndex[webViewID] == nil)
                    assert(pendingCleanupByWebViewID[webViewID] == nil)
                    expectedRetirementIndex[webViewID] = lease
                }
            }
            assert(
                expectedRetirementIndex == retirementLeaseByWebViewID,
                "Retirement identity index diverged during \(context)"
            )
        #else
            _ = context
        #endif
    }

    private func resumePendingCleanupWaitersIfPossible() {
        guard pendingCleanupByWebViewID.isEmpty else { return }
        resumeAllPendingCleanupWaiters(returning: true)
    }

    private func resumePendingCleanupWaiter(
        _ waiterID: UUID,
        returning result: Bool
    ) {
        pendingCleanupWaiters.removeValue(forKey: waiterID)?.resume(
            returning: result
        )
    }

    private func resumeAllPendingCleanupWaiters(returning result: Bool) {
        let waiters = pendingCleanupWaiters.values
        pendingCleanupWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    private func resumeOwnershipTransitionWaitersIfPossible() {
        guard !hasTransitions else { return }
        resumeAllOwnershipTransitionWaiters(returning: true)
    }

    private func resumeOwnershipTransitionWaiter(
        _ waiterID: UUID,
        returning result: Bool
    ) {
        ownershipTransitionWaiters.removeValue(forKey: waiterID)?.resume(
            returning: result
        )
    }

    private func resumeAllOwnershipTransitionWaiters(returning result: Bool) {
        let waiters = ownershipTransitionWaiters.values
        ownershipTransitionWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    private static func webViewIdentityOrder(
        _ lhs: WebViewPendingCleanupEntry,
        _ rhs: WebViewPendingCleanupEntry
    ) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs.webView))
            < UInt(bitPattern: ObjectIdentifier(rhs.webView))
    }

    private static func webViewIdentityOrder(
        _ lhs: WebViewRetirementEntry,
        _ rhs: WebViewRetirementEntry
    ) -> Bool {
        UInt(bitPattern: ObjectIdentifier(lhs.webView))
            < UInt(bitPattern: ObjectIdentifier(rhs.webView))
    }
}
