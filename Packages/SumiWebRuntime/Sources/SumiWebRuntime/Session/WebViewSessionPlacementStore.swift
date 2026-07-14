import Foundation
import WebKit

struct WebViewSessionPlacementRecord {
    var revision: UInt64 = 0
    var parkedWebView: WKWebView?
    var untrackedWebView: WKWebView?
    var primaryWindowID: UUID?
    var windowWebViews: [UUID: WKWebView] = [:]

    var isEmpty: Bool {
        parkedWebView == nil
            && untrackedWebView == nil
            && primaryWindowID == nil
            && windowWebViews.isEmpty
    }
}

/// Canonical strong ownership for active tab placements. Reverse residence and
/// window indexes contain identities only; `Entry` is the sole active owner of
/// each `WKWebView`.
@MainActor
final class WebViewSessionPlacementStore {
    typealias Entry = WebViewSessionPlacementRecord

    private var entries: [UUID: Entry] = [:]
    private var mutationRevision: UInt64 = 0
    private var index = WebViewSessionPlacementIndex()

    var residenceGeneration: UInt64 { mutationRevision }
    var tabIDs: Set<UUID> { Set(entries.keys) }
    var hasActiveResidences: Bool { !index.isEmpty }
    var activeResidences: [ObjectIdentifier: WebViewResidence] {
        index.residences
    }

    func advanceResidenceGeneration() {
        mutationRevision &+= 1
    }

    func snapshot(for tabID: UUID) -> WebViewSessionSnapshot {
        let entry = entries[tabID] ?? Entry()
        return WebViewSessionSnapshot(
            generation: generation(for: tabID),
            parkedWebView: entry.parkedWebView,
            untrackedWebView: entry.untrackedWebView,
            primaryWindowID: entry.primaryWindowID,
            windowWebViews: entry.windowWebViews
        )
    }

    func generation(for tabID: UUID) -> UInt64 {
        entries[tabID]?.revision ?? mutationRevision
    }

    func entry(for tabID: UUID) -> Entry? {
        entries[tabID]
    }

    func entry(from snapshot: WebViewSessionSnapshot) -> Entry {
        Entry(
            parkedWebView: snapshot.parkedWebView,
            untrackedWebView: snapshot.untrackedWebView,
            primaryWindowID: snapshot.primaryWindowID,
            windowWebViews: snapshot.windowWebViews
        )
    }

    func installRetirementReservation(for tabID: UUID) {
        let previousWindowIDs = Set(
            entries[tabID]?.windowWebViews.keys.map(\.self) ?? []
        )
        mutationRevision &+= 1
        var reservation = Entry()
        reservation.revision = mutationRevision
        entries[tabID] = reservation
        index.replaceWindowMembership(
            for: tabID,
            previousWindowIDs: previousWindowIDs,
            replacementWindowIDs: []
        )
    }

    func removeRetirementReservation(for tabID: UUID) {
        guard let reservation = entries[tabID], reservation.isEmpty else {
            preconditionFailure("Retirement reservation was not current")
        }
        storeMutated(Entry(), for: tabID)
    }

    func restoreExactly(
        _ snapshot: WebViewSessionSnapshot,
        for tabID: UUID
    ) {
        guard let reservation = entries[tabID], reservation.isEmpty,
              !snapshot.allKnownWebViews.isEmpty else {
            preconditionFailure("Retirement rollback state was not current")
        }
        mutationRevision &+= 1
        var restored = entry(from: snapshot)
        restored.revision = snapshot.generation
        entries[tabID] = restored
        index.replaceWindowMembership(
            for: tabID,
            previousWindowIDs: [],
            replacementWindowIDs: Set(restored.windowWebViews.keys)
        )
        installActiveResidences(in: restored, tabID: tabID)
    }

    func residence(of webView: WKWebView) -> WebViewResidence? {
        index.residence(of: webView)
    }

    func residence(with identifier: ObjectIdentifier) -> WebViewResidence? {
        index.residence(with: identifier)
    }

    func webView(with identifier: ObjectIdentifier) -> WKWebView? {
        guard let residence = index.residence(with: identifier) else {
            return nil
        }
        let webView: WKWebView?
        switch residence {
        case .parked(let tabID):
            webView = entries[tabID]?.parkedWebView
        case .untracked(let tabID):
            webView = entries[tabID]?.untrackedWebView
        case .window(let owner):
            webView = entries[owner.tabID]?.windowWebViews[owner.windowID]
        case .retiring, .pendingCleanup:
            assertionFailure("Transition residence leaked into placement store")
            return nil
        }
        guard let webView, ObjectIdentifier(webView) == identifier else {
            assertionFailure("Stale active WebView residence for \(identifier)")
            return nil
        }
        return webView
    }

    func untrackedWebView(for tabID: UUID) -> WKWebView? {
        entries[tabID]?.untrackedWebView
    }

    func parkedWebView(for tabID: UUID) -> WKWebView? {
        entries[tabID]?.parkedWebView
    }

    func primaryWindowID(for tabID: UUID) -> UUID? {
        entries[tabID]?.primaryWindowID
    }

    func primaryWebView(for tabID: UUID) -> WKWebView? {
        guard let entry = entries[tabID],
              let primaryWindowID = entry.primaryWindowID else { return nil }
        return entry.windowWebViews[primaryWindowID]
    }

    func currentWebView(for tabID: UUID) -> WKWebView? {
        primaryWebView(for: tabID) ?? untrackedWebView(for: tabID)
    }

    func allKnownWebViews(for tabID: UUID) -> [WKWebView] {
        snapshot(for: tabID).allKnownWebViews
    }

    func noteParkedWebView(_ webView: WKWebView?, for tabID: UUID) {
        replaceDetachedWebView(
            webView,
            residence: .parked(tabID: tabID),
            keyPath: \.parkedWebView
        )
    }

    func noteUntrackedWebView(_ webView: WKWebView?, for tabID: UUID) {
        if webView != nil {
            precondition(
                entries[tabID]?.windowWebViews.isEmpty != false,
                "Cannot activate an untracked WebView while window-owned WebViews exist"
            )
        }
        replaceDetachedWebView(
            webView,
            residence: .untracked(tabID: tabID),
            keyPath: \.untrackedWebView
        )
    }

    func adoptParkedWebViewAsUntracked(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        guard entries[tabID]?.parkedWebView === webView else { return false }
        noteUntrackedWebView(webView, for: tabID)
        return true
    }

    func clearDetachedWebViews(for tabID: UUID) {
        guard var entry = entries[tabID],
              entry.parkedWebView != nil || entry.untrackedWebView != nil else {
            return
        }
        removeResidence(for: entry.parkedWebView, expected: .parked(tabID: tabID))
        removeResidence(
            for: entry.untrackedWebView,
            expected: .untracked(tabID: tabID)
        )
        entry.parkedWebView = nil
        entry.untrackedWebView = nil
        storeMutated(entry, for: tabID)
    }

    func removeDetachedWebView(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        guard var entry = entries[tabID] else { return false }
        var didRemove = false
        if entry.parkedWebView === webView {
            entry.parkedWebView = nil
            removeResidence(for: webView, expected: .parked(tabID: tabID))
            didRemove = true
        }
        if entry.untrackedWebView === webView {
            entry.untrackedWebView = nil
            removeResidence(for: webView, expected: .untracked(tabID: tabID))
            didRemove = true
        }
        guard didRemove else { return false }
        storeMutated(entry, for: tabID)
        return true
    }

    func promoteTrackedWebViewToPrimary(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView
    ) -> Bool {
        guard var entry = entries[owner.tabID],
              entry.windowWebViews[owner.windowID] === expectedWebView else {
            return false
        }
        if entry.primaryWindowID == owner.windowID {
            return true
        }
        entry.primaryWindowID = owner.windowID
        storeMutated(entry, for: owner.tabID)
        return true
    }

    var isTrackingEmpty: Bool {
        entries.values.allSatisfy(\.windowWebViews.isEmpty)
    }

    var totalTrackedWebViewCount: Int {
        entries.values.reduce(0) { $0 + $1.windowWebViews.count }
    }

    func webView(for tabID: UUID, in windowID: UUID) -> WKWebView? {
        entries[tabID]?.windowWebViews[windowID]
    }

    func webView(for owner: TrackedWebViewOwner) -> WKWebView? {
        webView(for: owner.tabID, in: owner.windowID)
    }

    func webViews(for tabID: UUID) -> [WKWebView] {
        guard let entry = entries[tabID] else { return [] }
        return Array(entry.windowWebViews.values)
    }

    func windowWebViews(for tabID: UUID) -> [UUID: WKWebView] {
        entries[tabID]?.windowWebViews ?? [:]
    }

    func windowIDs(for tabID: UUID) -> [UUID] {
        guard let entry = entries[tabID] else { return [] }
        return Array(entry.windowWebViews.keys)
    }

    func trackedWebViews() -> [(TrackedWebViewOwner, WKWebView)] {
        entries.flatMap { tabID, entry in
            entry.windowWebViews.map { windowID, webView in
                (TrackedWebViewOwner(tabID: tabID, windowID: windowID), webView)
            }
        }
    }

    func trackedWebViews(
        for tabID: UUID
    ) -> [(TrackedWebViewOwner, WKWebView)] {
        windowWebViews(for: tabID).map { windowID, webView in
            (TrackedWebViewOwner(tabID: tabID, windowID: windowID), webView)
        }
    }

    func trackedWebViews(
        in windowID: UUID
    ) -> [(TrackedWebViewOwner, WKWebView)] {
        index.trackedTabIDs(in: windowID).compactMap { tabID in
            guard let webView = entries[tabID]?.windowWebViews[windowID] else {
                assertionFailure("Stale tracked-window index")
                return nil
            }
            return (
                TrackedWebViewOwner(tabID: tabID, windowID: windowID),
                webView
            )
        }
    }

    func trackedOwner(
        with identifier: ObjectIdentifier
    ) -> TrackedWebViewOwner? {
        guard case .window(let owner) = index.residence(with: identifier)
        else { return nil }
        guard let webView = webView(for: owner),
              ObjectIdentifier(webView) == identifier else {
            assertionFailure("Stale window residence for \(identifier)")
            return nil
        }
        return owner
    }

    func trackedWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        guard case .window = index.residence(with: identifier) else {
            return nil
        }
        return webView(with: identifier)
    }

    func indexedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        guard case .window(let owner) = residence(of: webView) else { return nil }
        return owner
    }

    func commitWindowRegistration(
        _ webView: WKWebView,
        for owner: TrackedWebViewOwner,
        candidateResidence: WebViewResidence?,
        trackedOccupant: WKWebView?,
        untrackedOccupant: WKWebView?
    ) -> WebViewWindowSlotRegistrationCommit {
        var entry = entries[owner.tabID] ?? Entry()
        let previousPrimaryWindowID = entry.primaryWindowID
        let vacatedOwner: TrackedWebViewOwner?

        switch candidateResidence {
        case .parked(let tabID):
            entry.parkedWebView = nil
            removeResidence(for: webView, expected: .parked(tabID: tabID))
            vacatedOwner = nil
        case .untracked(let tabID):
            entry.untrackedWebView = nil
            removeResidence(for: webView, expected: .untracked(tabID: tabID))
            vacatedOwner = nil
        case .window(let previousOwner):
            entry.windowWebViews.removeValue(forKey: previousOwner.windowID)
            removeResidence(for: webView, expected: .window(previousOwner))
            vacatedOwner = previousOwner
        case .retiring, .pendingCleanup:
            preconditionFailure(
                "A transition WebView cannot enter a tracked slot"
            )
        case nil:
            vacatedOwner = nil
        }

        let displacedTrackedWebView: WKWebView?
        if let trackedOccupant, trackedOccupant !== webView {
            entry.windowWebViews.removeValue(forKey: owner.windowID)
            removeResidence(for: trackedOccupant, expected: .window(owner))
            displacedTrackedWebView = trackedOccupant
        } else {
            displacedTrackedWebView = nil
        }

        let displacedUntrackedWebView: WKWebView?
        if let untrackedOccupant, untrackedOccupant !== webView {
            entry.untrackedWebView = nil
            removeResidence(
                for: untrackedOccupant,
                expected: .untracked(tabID: owner.tabID)
            )
            displacedUntrackedWebView = untrackedOccupant
        } else {
            displacedUntrackedWebView = nil
        }

        entry.windowWebViews[owner.windowID] = webView
        if previousPrimaryWindowID == vacatedOwner?.windowID
            || previousPrimaryWindowID == owner.windowID
            || previousPrimaryWindowID == nil {
            entry.primaryWindowID = owner.windowID
        } else if let previousPrimaryWindowID,
                  entry.windowWebViews[previousPrimaryWindowID] != nil {
            entry.primaryWindowID = previousPrimaryWindowID
        } else {
            entry.primaryWindowID = owner.windowID
        }

        index.install(.window(owner), for: webView)
        storeMutated(entry, for: owner.tabID)
        return WebViewWindowSlotRegistrationCommit(
            vacatedOwner: vacatedOwner,
            displacedTrackedWebView: displacedTrackedWebView,
            displacedUntrackedWebView: displacedUntrackedWebView,
            generation: generation(for: owner.tabID)
        )
    }

    func removeWindowWebView(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView?
    ) -> WKWebView? {
        guard var entry = entries[owner.tabID],
              let current = entry.windowWebViews[owner.windowID] else {
            return nil
        }
        if let expectedWebView, current !== expectedWebView {
            return nil
        }
        entry.windowWebViews.removeValue(forKey: owner.windowID)
        if entry.primaryWindowID == owner.windowID {
            entry.primaryWindowID = entry.windowWebViews.keys.min {
                $0.uuidString < $1.uuidString
            }
        }
        removeResidence(for: current, expected: .window(owner))
        storeMutated(entry, for: owner.tabID)
        return current
    }

    func replaceWindowSet(
        for tabID: UUID,
        expectedGeneration: UInt64,
        webViewsByWindowID: [UUID: WKWebView],
        primaryWindowID: UUID
    ) -> WebViewWindowSetReplacementResult {
        let currentGeneration = generation(for: tabID)
        guard currentGeneration == expectedGeneration else {
            return .stale(currentGeneration: currentGeneration)
        }
        guard webViewsByWindowID[primaryWindowID] != nil else {
            return .invalid
        }
        let identifiers = webViewsByWindowID.values.map(ObjectIdentifier.init)
        guard Set(identifiers).count == identifiers.count,
              webViewsByWindowID.values.allSatisfy({ residence(of: $0) == nil })
        else { return .invalid }

        let previous = snapshot(for: tabID)
        removeAllResidences(in: previous, tabID: tabID)
        var replacement = Entry()
        replacement.primaryWindowID = primaryWindowID
        replacement.windowWebViews = webViewsByWindowID
        storeMutated(replacement, for: tabID)
        installActiveResidences(in: replacement, tabID: tabID)
        return .committed(previous: previous)
    }

    func clearAll(for tabID: UUID) {
        let previous = snapshot(for: tabID)
        guard !previous.allKnownWebViews.isEmpty
                || previous.primaryWindowID != nil else { return }
        removeAllResidences(in: previous, tabID: tabID)
        storeMutated(Entry(), for: tabID)
    }

    func removeAllResidences(
        in snapshot: WebViewSessionSnapshot,
        tabID: UUID
    ) {
        removeResidence(
            for: snapshot.parkedWebView,
            expected: .parked(tabID: tabID)
        )
        removeResidence(
            for: snapshot.untrackedWebView,
            expected: .untracked(tabID: tabID)
        )
        for (windowID, webView) in snapshot.windowWebViews {
            removeResidence(
                for: webView,
                expected: .window(.init(tabID: tabID, windowID: windowID))
            )
        }
    }

    func removeResidence(
        for webView: WKWebView?,
        expected: WebViewResidence
    ) {
        guard let webView else { return }
        index.remove(webView, expected: expected)
    }

    func installActiveResidences(in entry: Entry, tabID: UUID) {
        if let parkedWebView = entry.parkedWebView {
            index.install(.parked(tabID: tabID), for: parkedWebView)
        }
        if let untrackedWebView = entry.untrackedWebView {
            index.install(.untracked(tabID: tabID), for: untrackedWebView)
        }
        for (windowID, webView) in entry.windowWebViews {
            index.install(
                .window(.init(tabID: tabID, windowID: windowID)),
                for: webView
            )
        }
    }

    func storeMutated(_ entry: Entry, for tabID: UUID) {
        let previousWindowWebViews = entries[tabID]?.windowWebViews ?? [:]
        mutationRevision &+= 1
        if entry.isEmpty {
            entries.removeValue(forKey: tabID)
        } else {
            var entry = entry
            entry.revision = mutationRevision
            entries[tabID] = entry
        }
        index.replaceWindowMembership(
            for: tabID,
            previousWindowIDs: Set(previousWindowWebViews.keys),
            replacementWindowIDs: Set(entry.windowWebViews.keys)
        )
    }

    func drainActiveResidences() -> [WebViewTerminalCleanupEntry] {
        let cleanupEntries = index.residences.map { webViewID, residence in
            guard let webView = webView(with: webViewID) else {
                preconditionFailure(
                    "Canonical active residence could not be resolved"
                )
            }
            return WebViewTerminalCleanupEntry(
                webView: webView,
                residence: residence
            )
        }
        entries.removeAll()
        index.removeAll()
        return cleanupEntries
    }

    func assertConsistency(_ context: StaticString) {
        #if DEBUG
            index.assertMatches(entries, context: context)
        #else
            _ = context
        #endif
    }

    private func replaceDetachedWebView(
        _ webView: WKWebView?,
        residence: WebViewResidence,
        keyPath: WritableKeyPath<Entry, WKWebView?>
    ) {
        let tabID = residence.tabID
        var entry = entries[tabID] ?? Entry()
        let previous = entry[keyPath: keyPath]
        if previous === webView { return }

        if let webView, let existingResidence = self.residence(of: webView) {
            precondition(
                existingResidence.tabID == tabID,
                "A WKWebView cannot be moved between tab sessions"
            )
        }

        removeResidence(for: previous, expected: residence)
        if let webView {
            guard case .window = self.residence(of: webView) else {
                detachNonWindowResidence(of: webView)
                entry = entries[tabID] ?? Entry()
                entry[keyPath: keyPath] = webView
                index.install(residence, for: webView)
                storeMutated(entry, for: tabID)
                return
            }
            preconditionFailure(
                "A tracked WebView cannot move through a tab-owned handle"
            )
        }

        entry[keyPath: keyPath] = nil
        storeMutated(entry, for: tabID)
    }

    private func detachNonWindowResidence(of webView: WKWebView) {
        switch residence(of: webView) {
        case .parked(let tabID):
            guard var entry = entries[tabID],
                  entry.parkedWebView === webView else { return }
            entry.parkedWebView = nil
            removeResidence(for: webView, expected: .parked(tabID: tabID))
            storeMutated(entry, for: tabID)
        case .untracked(let tabID):
            guard var entry = entries[tabID],
                  entry.untrackedWebView === webView else { return }
            entry.untrackedWebView = nil
            removeResidence(for: webView, expected: .untracked(tabID: tabID))
            storeMutated(entry, for: tabID)
        case .retiring:
            preconditionFailure(
                "A retiring WebView cannot return to a tab-owned slot"
            )
        case .pendingCleanup:
            preconditionFailure(
                "A WebView leased for cleanup cannot return to a tab-owned slot"
            )
        case .window, nil:
            break
        }
    }
}
