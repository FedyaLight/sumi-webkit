import Foundation
import WebKit

/// Read-only projection across active placements and in-flight ownership
/// transitions. It never mutates or retains WebViews independently.
@preconcurrency @MainActor
public final class WebViewSessionQueryService {
    private let placements: WebViewSessionPlacementStore
    private let transitions: WebViewOwnershipTransitionLedger

    init(
        placements: WebViewSessionPlacementStore,
        transitions: WebViewOwnershipTransitionLedger
    ) {
        self.placements = placements
        self.transitions = transitions
    }

    public func snapshot(for tabID: UUID) -> WebViewSessionSnapshot {
        placements.snapshot(for: tabID)
    }

    public func generation(for tabID: UUID) -> UInt64 {
        placements.generation(for: tabID)
    }

    public var residenceGeneration: UInt64 {
        placements.residenceGeneration
    }

    public func pendingCleanupSnapshot() -> WebViewPendingCleanupSnapshot {
        transitions.pendingCleanupSnapshot(generation: residenceGeneration)
    }

    public func ownershipTransitionSnapshot()
        -> WebViewOwnershipTransitionSnapshot {
        transitions.ownershipTransitionSnapshot(
            generation: residenceGeneration
        )
    }

    public func waitUntilPendingCleanupIsEmpty() async -> Bool {
        await transitions.waitUntilPendingCleanupIsEmpty()
    }

    public func waitUntilOwnershipTransitionsAreSettled() async -> Bool {
        await transitions.waitUntilSettled()
    }

    public func hasOwnershipTransition(for tabID: UUID) -> Bool {
        transitions.pendingCleanupTabIDs.contains(tabID)
            || transitions.retirementTabIDs.contains(tabID)
    }

    public func residence(of webView: WKWebView) -> WebViewResidence? {
        let active = placements.residence(of: webView)
        let transition = transitions.residence(of: webView)
        assert(active == nil || transition == nil)
        return active ?? transition
    }

    public func webView(with identifier: ObjectIdentifier) -> WKWebView? {
        let active = placements.webView(with: identifier)
        let transition = transitions.webView(with: identifier)
        assert(active == nil || transition == nil)
        return active ?? transition
    }

    public func untrackedWebView(for tabID: UUID) -> WKWebView? {
        placements.untrackedWebView(for: tabID)
    }

    public func parkedWebView(for tabID: UUID) -> WKWebView? {
        placements.parkedWebView(for: tabID)
    }

    public func primaryWindowID(for tabID: UUID) -> UUID? {
        placements.primaryWindowID(for: tabID)
    }

    public func primaryWebView(for tabID: UUID) -> WKWebView? {
        placements.primaryWebView(for: tabID)
    }

    public func currentWebView(for tabID: UUID) -> WKWebView? {
        placements.currentWebView(for: tabID)
    }

    public func allKnownWebViews(for tabID: UUID) -> [WKWebView] {
        placements.allKnownWebViews(for: tabID)
    }

    public func runtimeOwnedWebViews(for tabID: UUID) -> [WKWebView] {
        uniqueWebViews(
            placements.allKnownWebViews(for: tabID)
                + transitions.retirementWebViews(for: tabID)
        )
    }

    public var runtimeOwnedTabIDs: Set<UUID> {
        placements.tabIDs
            .union(transitions.retirementTabIDs)
            .union(transitions.pendingCleanupTabIDs)
    }

    public var isTrackingEmpty: Bool { placements.isTrackingEmpty }

    public var totalTrackedWebViewCount: Int {
        placements.totalTrackedWebViewCount
    }

    public func webView(for tabID: UUID, in windowID: UUID) -> WKWebView? {
        placements.webView(for: tabID, in: windowID)
    }

    public func webView(for owner: TrackedWebViewOwner) -> WKWebView? {
        placements.webView(for: owner)
    }

    public func webViews(for tabID: UUID) -> [WKWebView] {
        placements.webViews(for: tabID)
    }

    public func windowWebViews(for tabID: UUID) -> [UUID: WKWebView] {
        placements.windowWebViews(for: tabID)
    }

    public func windowIDs(for tabID: UUID) -> [UUID] {
        placements.windowIDs(for: tabID)
    }

    public func trackedWebViews() -> [(TrackedWebViewOwner, WKWebView)] {
        placements.trackedWebViews()
    }

    public func trackedWebViews(
        for tabID: UUID
    ) -> [(TrackedWebViewOwner, WKWebView)] {
        placements.trackedWebViews(for: tabID)
    }

    public func trackedWebViews(
        in windowID: UUID
    ) -> [(TrackedWebViewOwner, WKWebView)] {
        placements.trackedWebViews(in: windowID)
    }

    public func trackedOwner(
        with identifier: ObjectIdentifier
    ) -> TrackedWebViewOwner? {
        placements.trackedOwner(with: identifier)
    }

    public func trackedWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        placements.trackedWebView(with: identifier)
    }

    public func trackedOwner(
        containing webView: WKWebView
    ) -> TrackedWebViewOwner? {
        placements.indexedOwner(containing: webView)
    }

    public func isIndexed(_ webView: WKWebView) -> Bool {
        trackedOwner(containing: webView) != nil
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        return webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }
}
