import Foundation
import OSLog

@MainActor
final class TabSuspensionStateOwner {
    var isSuspended = false
    var lastSuspendedURL: URL?
    var lastSelectedAt: Date?
    var pageSuspensionVeto: TabPageSuspensionVeto = .none
    var hasPictureInPictureVideo = false
    var isDisplayingPDFDocument = false
    var isRestoreInProgress = false
    private var restoreTraceState: OSSignpostIntervalState?

    func noteAccess(at date: Date = Date()) {
        lastSelectedAt = date
    }

    func resetRuntimeState() {
        pageSuspensionVeto = .none
        hasPictureInPictureVideo = false
        isDisplayingPDFDocument = false
    }

    func markSuspended(tab: Tab, at date: Date = Date()) {
        tab.objectWillChange.send()
        isSuspended = true
        isRestoreInProgress = false
        lastSuspendedURL = tab.url
        if lastSelectedAt == nil {
            lastSelectedAt = date
        }
        tab.resetPlaybackActivity()
        tab.loadingState = .idle
        tab.stateChangeEmitter.postLifecycleDidChange(for: tab)
    }

    func beginRestoreIfNeeded() {
        guard isSuspended, !isRestoreInProgress else { return }
        isRestoreInProgress = true
        restoreTraceState = PerformanceTrace.beginInterval("TabSuspension.restore")
        PerformanceTrace.emitEvent("TabSuspension.restoreStart")
    }

    func finishRestoreIfNeeded(tab: Tab, hasWebView: Bool) {
        guard isRestoreInProgress, hasWebView else { return }
        tab.objectWillChange.send()
        isSuspended = false
        isRestoreInProgress = false
        if let traceState = restoreTraceState {
            PerformanceTrace.endInterval("TabSuspension.restore", traceState)
            restoreTraceState = nil
        }
        PerformanceTrace.emitEvent("TabSuspension.restoreEnd")
        tab.stateChangeEmitter.postLifecycleDidChange(for: tab)
    }
}
