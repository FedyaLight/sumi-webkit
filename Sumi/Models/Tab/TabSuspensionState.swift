import Foundation

struct TabSuspensionState {
    var isSuspended = false
    var lastSuspendedURL: URL?
    var isRestoreInProgress = false
    private(set) var interactionStateData: Data?
    private var restoreTraceState: PerformanceTrace.IntervalState?

    mutating func markSuspended(
        url: URL,
        interactionStateData: Data?
    ) {
        isSuspended = true
        isRestoreInProgress = false
        lastSuspendedURL = url
        self.interactionStateData = interactionStateData
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

    mutating func takeInteractionStateForRestore() -> Data? {
        defer { interactionStateData = nil }
        return interactionStateData
    }
}
