import Foundation
import Observation
import SumiDomain

/// Runtime receipts for one restore cycle.
/// This state is never encoded back into the durable window snapshot.
@MainActor
@Observable
final class WindowRestorationState {
    var restoredSessionWindowID: UUID?
    var isAwaitingInitialResolution: Bool
    var pendingSplitSelection: PendingWindowSplitSelection?
    private var pendingSnappedSidebarCorrection = false
    private(set) var pendingShortcutLiveSessions:
        [ShortcutLiveSessionSnapshot] = []
    private(set) var pendingWindowGeometry: BrowserWindowGeometrySnapshot?
    private var pendingWindowGeometryFrameShellIdentity: ObjectIdentifier?

    init(isAwaitingInitialResolution: Bool = false) {
        self.isAwaitingInitialResolution = isAwaitingInitialResolution
    }

    /// Stages that a session restore is correcting the sidebar visibility of an
    /// already-presented window after initial resolution. The presented layout
    /// must snap to the restored value instead of animating.
    func stageSnappedSidebarCorrection() {
        pendingSnappedSidebarCorrection = true
    }

    func consumeSnappedSidebarCorrection() -> Bool {
        defer { pendingSnappedSidebarCorrection = false }
        return pendingSnappedSidebarCorrection
    }

    func stageWindowGeometry(_ geometry: BrowserWindowGeometrySnapshot?) {
        pendingWindowGeometry = geometry
        pendingWindowGeometryFrameShellIdentity = nil
    }

    func stageShortcutLiveSessions(
        _ sessions: [ShortcutLiveSessionSnapshot]
    ) {
        pendingShortcutLiveSessions = sessions
    }

    func consumeShortcutLiveSessions() -> [ShortcutLiveSessionSnapshot] {
        defer { pendingShortcutLiveSessions = [] }
        return pendingShortcutLiveSessions
    }

    func needsPendingWindowGeometryFrame(for shell: AnyObject) -> Bool {
        pendingWindowGeometry != nil
            && pendingWindowGeometryFrameShellIdentity != ObjectIdentifier(shell)
    }

    func markPendingWindowGeometryFrameApplied(to shell: AnyObject) {
        guard pendingWindowGeometry != nil else { return }
        pendingWindowGeometryFrameShellIdentity = ObjectIdentifier(shell)
    }

    func consumePendingWindowGeometry() -> BrowserWindowGeometrySnapshot? {
        defer {
            pendingWindowGeometry = nil
            pendingWindowGeometryFrameShellIdentity = nil
        }
        return pendingWindowGeometry
    }
}
