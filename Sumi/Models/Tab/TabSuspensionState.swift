import Foundation
import OSLog

struct TabSuspensionState {
    var isSuspended = false
    var lastSuspendedURL: URL?
    var isRestoreInProgress = false
    private var restoreTraceState: OSSignpostIntervalState?

    mutating func markSuspended(url: URL) {
        isSuspended = true
        isRestoreInProgress = false
        lastSuspendedURL = url
    }

    mutating func beginRestoreIfNeeded() {
        guard isSuspended, !isRestoreInProgress else { return }
        isRestoreInProgress = true
        restoreTraceState = PerformanceTrace.beginInterval("TabSuspension.restore")
        PerformanceTrace.emitEvent("TabSuspension.restoreStart")
    }

    mutating func finishRestore() {
        guard isRestoreInProgress else { return }
        isSuspended = false
        isRestoreInProgress = false
        if let restoreTraceState {
            PerformanceTrace.endInterval("TabSuspension.restore", restoreTraceState)
            self.restoreTraceState = nil
        }
        PerformanceTrace.emitEvent("TabSuspension.restoreEnd")
    }
}
