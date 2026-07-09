import AppKit

struct SpaceSwipeGestureEvent: Equatable {
    enum Phase: Equatable {
        case began
        case changed
        case ended
        case cancelled
    }

    let phase: Phase
    let direction: Int?
    let progress: Double
}

enum SpaceSwipeGestureAxisLock: Equatable {
    case unresolved
    case horizontal
    case vertical
}

struct SpaceSwipeGestureSample: Equatable {
    var phase: NSEvent.Phase
    var momentumPhase: NSEvent.Phase
    var scrollingDeltaX: CGFloat
    var scrollingDeltaY: CGFloat
    var hasPreciseScrollingDeltas: Bool

    init(
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = [],
        scrollingDeltaX: CGFloat = 0,
        scrollingDeltaY: CGFloat = 0,
        hasPreciseScrollingDeltas: Bool = true
    ) {
        self.phase = phase
        self.momentumPhase = momentumPhase
        self.scrollingDeltaX = scrollingDeltaX
        self.scrollingDeltaY = scrollingDeltaY
        self.hasPreciseScrollingDeltas = hasPreciseScrollingDeltas
    }

    init(event: NSEvent) {
        self.init(
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            scrollingDeltaX: event.scrollingDeltaX,
            scrollingDeltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
    }
}

enum SpaceSwipeGestureHandling: Equatable {
    case consume
    case forwardToUnderlying
}

struct SpaceSwipeGestureTrackingResult: Equatable {
    var handling: SpaceSwipeGestureHandling
    var emittedEvents: [SpaceSwipeGestureEvent]
}

struct SpaceSwipeGestureTracker {
    private(set) var axisLock: SpaceSwipeGestureAxisLock = .unresolved
    private(set) var didSendBeginEvent = false
    private(set) var cumulativeDeltaX: CGFloat = 0
    private(set) var cumulativeDeltaY: CGFloat = 0
    private(set) var lastProgress: Double = 0
    private(set) var lastDirection: Int?

    mutating func process(
        _ sample: SpaceSwipeGestureSample,
        width: CGFloat,
        isEnabled: Bool
    ) -> SpaceSwipeGestureTrackingResult {
        guard isEnabled else {
            reset()
            return .init(handling: .forwardToUnderlying, emittedEvents: [])
        }

        guard sample.hasPreciseScrollingDeltas else {
            return .init(handling: .forwardToUnderlying, emittedEvents: [])
        }

        if !sample.momentumPhase.isEmpty {
            return .init(
                handling: axisLock == .horizontal ? .consume : .forwardToUnderlying,
                emittedEvents: []
            )
        }

        var emittedEvents: [SpaceSwipeGestureEvent] = []

        if sample.phase.contains(.began) || (!didSendBeginEvent && !sample.phase.isEmpty) {
            beginGestureIfNeeded(into: &emittedEvents)
        }

        if sample.phase.contains(.cancelled) {
            return finishTracking(
                phase: .cancelled,
                width: width,
                prefixEvents: emittedEvents
            )
        }

        if sample.phase.contains(.ended) {
            return handleEndedPhase(width: width, emittedEvents: emittedEvents)
        }

        if sample.phase.contains(.changed) || sample.phase.isEmpty {
            return handleChangedPhase(sample, width: width, emittedEvents: emittedEvents)
        }

        let shouldConsumeUnresolvedGesture = didSendBeginEvent && axisLock == .unresolved
        return .init(
            handling: (axisLock == .horizontal || shouldConsumeUnresolvedGesture)
                ? .consume
                : .forwardToUnderlying,
            emittedEvents: emittedEvents
        )
    }

    private mutating func handleEndedPhase(
        width: CGFloat,
        emittedEvents: [SpaceSwipeGestureEvent]
    ) -> SpaceSwipeGestureTrackingResult {
        switch axisLock {
        case .horizontal:
            return finishTracking(phase: .ended, width: width, prefixEvents: emittedEvents)
        case .unresolved:
            var events = emittedEvents
            events.append(.init(phase: .cancelled, direction: nil, progress: 0))
            reset()
            return .init(handling: .consume, emittedEvents: events)
        case .vertical:
            reset()
            return .init(handling: .forwardToUnderlying, emittedEvents: emittedEvents)
        }
    }

    private mutating func handleChangedPhase(
        _ sample: SpaceSwipeGestureSample,
        width: CGFloat,
        emittedEvents: [SpaceSwipeGestureEvent]
    ) -> SpaceSwipeGestureTrackingResult {
        var events = emittedEvents
        cumulativeDeltaX += sample.scrollingDeltaX
        cumulativeDeltaY += sample.scrollingDeltaY

        switch axisLock {
        case .unresolved:
            guard resolveAxisLock(into: &events) else {
                return .init(handling: axisLock == .vertical ? .forwardToUnderlying : .consume, emittedEvents: events)
            }
        case .vertical:
            return .init(handling: .forwardToUnderlying, emittedEvents: events)
        case .horizontal:
            break
        }

        appendProgressEvent(for: sample, width: width, into: &events)
        return .init(handling: .consume, emittedEvents: events)
    }

    private mutating func resolveAxisLock(into emittedEvents: inout [SpaceSwipeGestureEvent]) -> Bool {
        let absoluteX = abs(cumulativeDeltaX)
        let absoluteY = abs(cumulativeDeltaY)

        if absoluteX >= SpaceSidebarTransitionConfig.axisLockDistance,
           absoluteX > (absoluteY * SpaceSidebarTransitionConfig.axisLockDominanceMultiplier) {
            axisLock = .horizontal
            return true
        }

        if absoluteY >= SpaceSidebarTransitionConfig.axisLockDistance,
           absoluteY > (absoluteX * SpaceSidebarTransitionConfig.axisLockDominanceMultiplier) {
            axisLock = .vertical
            emittedEvents.append(.init(phase: .cancelled, direction: nil, progress: 0))
        }
        return false
    }

    private mutating func appendProgressEvent(
        for sample: SpaceSwipeGestureSample,
        width: CGFloat,
        into emittedEvents: inout [SpaceSwipeGestureEvent]
    ) {
        let resolvedWidth = max(width, 1)
        let directionSeed = abs(cumulativeDeltaX) > abs(sample.scrollingDeltaX)
            ? cumulativeDeltaX
            : sample.scrollingDeltaX
        let direction = SpaceSidebarSwipePhysics.latchedDirection(
            current: lastDirection,
            rawDeltaX: directionSeed
        )
        let progress = SpaceSidebarSwipePhysics.normalizedProgress(
            distance: abs(cumulativeDeltaX),
            width: resolvedWidth
        )
        let directionChanged = direction != lastDirection
        lastDirection = direction

        guard abs(progress - lastProgress) >= SpaceSidebarTransitionConfig.swipeProgressEpsilon || directionChanged else {
            return
        }

        lastProgress = progress
        emittedEvents.append(
            .init(
                phase: .changed,
                direction: direction,
                progress: progress
            )
        )
    }

    mutating func reset() {
        axisLock = .unresolved
        didSendBeginEvent = false
        cumulativeDeltaX = 0
        cumulativeDeltaY = 0
        lastProgress = 0
        lastDirection = nil
    }

    private mutating func beginGestureIfNeeded(into emittedEvents: inout [SpaceSwipeGestureEvent]) {
        guard !didSendBeginEvent else { return }
        didSendBeginEvent = true
        emittedEvents.append(.init(phase: .began, direction: nil, progress: 0))
    }

    private mutating func finishTracking(
        phase: SpaceSwipeGestureEvent.Phase,
        width: CGFloat,
        prefixEvents: [SpaceSwipeGestureEvent]
    ) -> SpaceSwipeGestureTrackingResult {
        guard axisLock == .horizontal else {
            reset()
            return .init(handling: .forwardToUnderlying, emittedEvents: prefixEvents)
        }

        let finalProgress = SpaceSidebarSwipePhysics.normalizedProgress(
            distance: abs(cumulativeDeltaX),
            width: max(width, 1)
        )

        var emittedEvents = prefixEvents
        emittedEvents.append(
            .init(
                phase: phase,
                direction: lastDirection,
                progress: finalProgress
            )
        )
        reset()
        return .init(handling: .consume, emittedEvents: emittedEvents)
    }
}
