import AppKit

@MainActor
final class WebKitGlanceCursorStabilizationOwner {
    struct Dependencies {
        let isEnabled: @MainActor () -> Bool
        let pointInView: @MainActor (NSEvent) -> CGPoint?
        let currentMousePointInView: @MainActor () -> CGPoint?
        let containsPoint: @MainActor (CGPoint) -> Bool
        let currentCursor: @MainActor () -> NSCursor
        let setCursor: @MainActor (NSCursor) -> Void
        let performDefaultMouseMoved: @MainActor (NSEvent) -> Void
        let scheduleSettleCapture: @MainActor (DispatchWorkItem) -> Void
        let currentTimestamp: @MainActor () -> TimeInterval
    }

    private static let cursorReuseDistance: CGFloat = 72
    private static let cursorReuseDistanceSquared = cursorReuseDistance * cursorReuseDistance
    private static let cursorReuseInterval: TimeInterval = 0.2

    private let dependencies: Dependencies
    private var settleToken = 0
    private var settleWorkItem: DispatchWorkItem?
    private var lastPageCursor: NSCursor?
    private var lastPageCursorPoint: CGPoint?
    private var lastPageCursorTimestamp: TimeInterval = 0

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func mouseMoved(with event: NSEvent) {
        guard let point = dependencies.pointInView(event) else {
            reset()
            return
        }

        let cursorBeforeMove = dependencies.currentCursor()
        dependencies.performDefaultMouseMoved(event)
        guard dependencies.containsPoint(point) else {
            reset()
            return
        }

        let cursorAfterMove = dependencies.currentCursor()
        if rememberPageCursorIfNeeded(cursorAfterMove, at: point, timestamp: event.timestamp) {
            scheduleSettleCapture()
            return
        }

        if !Self.isArrowCursor(cursorBeforeMove) {
            rememberPageCursor(cursorBeforeMove, at: point, timestamp: event.timestamp)
            dependencies.setCursor(cursorBeforeMove)
            scheduleSettleCapture()
            return
        }

        if let lastPageCursor,
           canReusePageCursor(at: point, timestamp: event.timestamp) {
            dependencies.setCursor(lastPageCursor)
        }
        scheduleSettleCapture()
    }

    func cursorUpdated(with event: NSEvent) {
        guard let point = dependencies.pointInView(event) else { return }
        _ = rememberPageCursorIfNeeded(dependencies.currentCursor(), at: point, timestamp: event.timestamp)
    }

    func reset() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        settleToken &+= 1
        lastPageCursor = nil
        lastPageCursorPoint = nil
        lastPageCursorTimestamp = 0
    }

    private static func isArrowCursor(_ cursor: NSCursor) -> Bool {
        cursor === NSCursor.arrow
    }

    private func rememberPageCursorIfNeeded(
        _ cursor: NSCursor,
        at point: CGPoint,
        timestamp: TimeInterval
    ) -> Bool {
        guard !Self.isArrowCursor(cursor),
              dependencies.containsPoint(point)
        else { return false }

        rememberPageCursor(cursor, at: point, timestamp: timestamp)
        return true
    }

    private func rememberPageCursor(
        _ cursor: NSCursor,
        at point: CGPoint,
        timestamp: TimeInterval
    ) {
        lastPageCursor = cursor
        lastPageCursorPoint = point
        lastPageCursorTimestamp = timestamp
    }

    private func canReusePageCursor(
        at point: CGPoint,
        timestamp: TimeInterval
    ) -> Bool {
        guard let lastPageCursorPoint else { return false }
        guard timestamp - lastPageCursorTimestamp <= Self.cursorReuseInterval else { return false }

        let dx = point.x - lastPageCursorPoint.x
        let dy = point.y - lastPageCursorPoint.y
        return dx * dx + dy * dy <= Self.cursorReuseDistanceSquared
    }

    private func scheduleSettleCapture() {
        settleWorkItem?.cancel()
        settleToken &+= 1
        let token = settleToken
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.dependencies.isEnabled(),
                      self.settleToken == token
                else { return }
                self.settleWorkItem = nil

                guard let currentPoint = self.dependencies.currentMousePointInView(),
                      self.dependencies.containsPoint(currentPoint)
                else {
                    self.reset()
                    return
                }

                let timestamp = self.dependencies.currentTimestamp()
                let cursor = self.dependencies.currentCursor()
                if !Self.isArrowCursor(cursor) {
                    self.rememberPageCursor(cursor, at: currentPoint, timestamp: timestamp)
                } else if !self.canReusePageCursor(at: currentPoint, timestamp: timestamp) {
                    self.reset()
                }
            }
        }
        settleWorkItem = workItem
        dependencies.scheduleSettleCapture(workItem)
    }
}
