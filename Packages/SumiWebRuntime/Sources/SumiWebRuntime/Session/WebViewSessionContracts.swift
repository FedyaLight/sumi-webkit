import Foundation
import WebKit

public struct TrackedWebViewOwner: Equatable, Hashable, Sendable {
    public let tabID: UUID
    public let windowID: UUID

    public init(tabID: UUID, windowID: UUID) {
        self.tabID = tabID
        self.windowID = windowID
    }
}

public struct WebViewPendingCleanupLease: Equatable, Hashable, Sendable {
    public let id: UUID
    public let tabID: UUID

    public init(id: UUID, tabID: UUID) {
        self.id = id
        self.tabID = tabID
    }
}

public struct WebViewReplacementBatchLease: Equatable, Hashable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct WebViewRetirementBatchLease: Equatable, Hashable, Sendable {
    public let id: UUID

    init(id: UUID) {
        self.id = id
    }
}

public struct WebViewRetirementLease: Equatable, Hashable, Sendable {
    public let batchID: UUID
    public let tabID: UUID

    public init(batchID: UUID, tabID: UUID) {
        self.batchID = batchID
        self.tabID = tabID
    }
}

public enum WebViewResidence: Equatable, Hashable, Sendable {
    case parked(tabID: UUID)
    case untracked(tabID: UUID)
    case window(TrackedWebViewOwner)
    case retiring(WebViewRetirementLease)
    case pendingCleanup(WebViewPendingCleanupLease)

    var tabID: UUID {
        switch self {
        case .parked(let tabID), .untracked(let tabID):
            return tabID
        case .window(let owner):
            return owner.tabID
        case .retiring(let lease):
            return lease.tabID
        case .pendingCleanup(let lease):
            return lease.tabID
        }
    }
}

public struct WebViewTerminalCleanupEntry {
    public let webView: WKWebView
    public let residence: WebViewResidence

    public var tabID: UUID { residence.tabID }

    init(webView: WKWebView, residence: WebViewResidence) {
        self.webView = webView
        self.residence = residence
    }
}

public struct WebViewPendingCleanupEntry {
    public let lease: WebViewPendingCleanupLease
    public let webView: WKWebView
}

public struct WebViewPendingCleanupSnapshot {
    public let generation: UInt64
    public let entries: [WebViewPendingCleanupEntry]

    public var isEmpty: Bool { entries.isEmpty }
}

public struct WebViewRetirementEntry {
    public let lease: WebViewRetirementLease
    public let webView: WKWebView
}

public struct WebViewOwnershipTransitionSnapshot {
    public let generation: UInt64
    public let pendingCleanupEntries: [WebViewPendingCleanupEntry]
    public let retirementEntries: [WebViewRetirementEntry]

    public var isEmpty: Bool {
        pendingCleanupEntries.isEmpty && retirementEntries.isEmpty
    }
}

public struct WebViewSessionSnapshot {
    public let generation: UInt64
    public let parkedWebView: WKWebView?
    public let untrackedWebView: WKWebView?
    public let primaryWindowID: UUID?
    public let windowWebViews: [UUID: WKWebView]

    public var allKnownWebViews: [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var result: [WKWebView] = []
        result.reserveCapacity(windowWebViews.count + 2)

        func append(_ webView: WKWebView?) {
            guard let webView,
                  seen.insert(ObjectIdentifier(webView)).inserted else { return }
            result.append(webView)
        }

        windowWebViews.values.forEach(append)
        append(untrackedWebView)
        append(parkedWebView)
        return result
    }
}

public enum WebViewWindowSetReplacementResult {
    case committed(previous: WebViewSessionSnapshot)
    case stale(currentGeneration: UInt64)
    case invalid
}

public enum WebViewDetachedReplacementResidence: Equatable, Sendable {
    case parked
    case untracked
}

public enum WebViewReplacementPlacement {
    case windowSet(
        webViewsByWindowID: [UUID: WKWebView],
        primaryWindowID: UUID
    )
    case detached(
        webView: WKWebView,
        residence: WebViewDetachedReplacementResidence
    )
}

public struct WebViewReplacementBatchEntry {
    public let tabID: UUID
    public let expectedGeneration: UInt64
    public let placement: WebViewReplacementPlacement

    public init(
        tabID: UUID,
        expectedGeneration: UInt64,
        placement: WebViewReplacementPlacement
    ) {
        self.tabID = tabID
        self.expectedGeneration = expectedGeneration
        self.placement = placement
    }
}

public struct WebViewRetirementBatchEntry: Equatable, Sendable {
    public let tabID: UUID
    public let expectedGeneration: UInt64

    public init(tabID: UUID, expectedGeneration: UInt64) {
        self.tabID = tabID
        self.expectedGeneration = expectedGeneration
    }
}

/// Exact model state shared by the caller and one retirement batch.
@MainActor
public final class WebViewRetirementModelTransactionReceipt {
    public enum State: Equatable {
        case prepared, modelStaged, modelRolledBack, conflicted
    }

    let id: UUID
    private let isCurrentAction: @MainActor () -> Bool
    private let commitAction: @MainActor () -> Bool
    private let rollbackAction: @MainActor () -> Bool
    public private(set) var state = State.prepared

    public init(
        isCurrent: @escaping @MainActor () -> Bool,
        commit: @escaping @MainActor () -> Bool,
        rollback: @escaping @MainActor () -> Bool
    ) {
        id = UUID()
        isCurrentAction = isCurrent
        commitAction = commit
        rollbackAction = rollback
    }

    func isCurrent() -> Bool {
        state == .prepared && isCurrentAction()
    }

    @discardableResult
    func commit() -> Bool {
        guard state == .prepared else { return false }
        state = .conflicted
        guard commitAction() else { return false }
        state = .modelStaged
        return true
    }

    @discardableResult
    func rollback() -> Bool {
        guard state == .modelStaged else { return false }
        state = .conflicted
        guard rollbackAction() else { return false }
        state = .modelRolledBack
        return true
    }
}

public enum WebViewReplacementBatchBeginResult {
    case began(WebViewReplacementBatchLease)
    case stale(tabID: UUID, currentGeneration: UInt64)
    case conflict(tabID: UUID)
    case invalid(tabID: UUID?)
    /// Model admission rejected before repository apply. The caller retains
    /// ownership of every prepared replacement.
    case modelValidationFailed
    /// Model commit was compensated and repository ownership was restored.
    /// The caller now owns physical cleanup of the discarded generation.
    case modelCommitFailed(discarded: [UUID: WebViewSessionSnapshot])
    /// Model compensation failed while the repository still owned both
    /// generations. The lease remains quarantined until terminal drain.
    case modelRollbackFailed(WebViewReplacementBatchLease)
    case noLongerActive
}

public enum WebViewReplacementBatchCommitResult {
    case committed(retired: [UUID: WebViewSessionSnapshot])
    case noLongerActive
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

public enum WebViewReplacementBatchRollbackResult {
    case rolledBack(discarded: [UUID: WebViewSessionSnapshot])
    /// Terminal repository ownership already consumed both generations.
    case terminallyDrained
    /// Model compensation failed before repository restoration. Both
    /// generations remain quarantined under the claimed rollback lease.
    case modelRollbackFailed
    case noLongerActive
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

public enum WebViewRetirementBatchBeginResult {
    case began(WebViewRetirementBatchLease)
    case stale(tabID: UUID, currentGeneration: UInt64)
    case conflict(tabID: UUID)
    case invalid(tabID: UUID?)
    case modelValidationFailed
    case modelConflict(WebViewRetirementBatchLease)
    case noLongerActive
}

public enum WebViewRetirementBatchCommitResult {
    case committed(retired: [UUID: WebViewSessionSnapshot])
    case noLongerActive
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

public enum WebViewRetirementBatchRollbackResult {
    case rolledBack
    case noLongerActive
    case modelTransactionMismatch
    case modelConflict
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

public enum WebViewRetirementModelConflictRestoreResult {
    case restored
    case noLongerActive
    case conflict(tabID: UUID, currentGeneration: UInt64)
}

public enum WebViewRetirementCleanupClaimResult {
    case claimed(retired: [UUID: WebViewSessionSnapshot])
    case noLongerActive
}

public struct WebViewPendingCleanupClaim {
    public let webView: WKWebView
    public let lease: WebViewPendingCleanupLease
}

public enum WebViewDetachedSetReplacementResult {
    case committed(displaced: [WebViewPendingCleanupClaim])
    case stale(currentGeneration: UInt64)
    case invalid
}

package enum WebViewWindowSlotRegistrationRejection: Equatable {
    case crossTabCandidate
    case inconsistentIdentity
    case pendingCleanupCandidate
    case protectedCandidate
    case protectedTrackedOccupant
    case protectedUntrackedOccupant
    case changedDuringPreflight
}

package struct WebViewWindowSlotRegistrationCommit {
    package let vacatedOwner: TrackedWebViewOwner?
    package let displacedTrackedWebView: WKWebView?
    package let displacedUntrackedWebView: WKWebView?
    package let generation: UInt64
}

package enum WebViewWindowSlotRegistrationResult {
    case unchanged
    case committed(WebViewWindowSlotRegistrationCommit)
    case rejected(WebViewWindowSlotRegistrationRejection)
}
