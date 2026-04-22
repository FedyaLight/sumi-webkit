import AppKit

enum SpaceSidebarTransitionConfig {
    static let spaceSwitchAnimationDuration: Double = 0.37

    static let swipeCommitThreshold: Double = 0.3
    static let directionLatchThreshold: CGFloat = 0.8
    static let interactiveTailCompressionStart: Double = 0.82
    static let interactiveCompletionReserve: Double = 0.08

    static let swipeProgressEpsilon: Double = 0.01
    static let axisLockDistance: CGFloat = 2
    static let axisLockDominanceMultiplier: CGFloat = 1.15
}

enum SpaceSidebarTransitionPhase: Equatable {
    case idle
    case clickAnimating
    case interactive
    case settling
}

enum SpaceSidebarTransitionTrigger: Equatable {
    case click
    case swipe
}

struct SpaceSidebarSwipePhysics {
    static func normalizedProgress(
        distance: CGFloat,
        width: CGFloat
    ) -> Double {
        let clampedLinearProgress = min(1, max(0, Double(distance / max(width, 1))))

        guard clampedLinearProgress > SpaceSidebarTransitionConfig.interactiveTailCompressionStart else {
            return clampedLinearProgress
        }

        let compressedMaxProgress = 1 - SpaceSidebarTransitionConfig.interactiveCompletionReserve
        let inputRange = 1 - SpaceSidebarTransitionConfig.interactiveTailCompressionStart
        let outputRange = compressedMaxProgress - SpaceSidebarTransitionConfig.interactiveTailCompressionStart
        let normalizedTailProgress = (clampedLinearProgress - SpaceSidebarTransitionConfig.interactiveTailCompressionStart) / inputRange

        return SpaceSidebarTransitionConfig.interactiveTailCompressionStart + (normalizedTailProgress * outputRange)
    }

    static func latchedDirection(
        current: Int?,
        rawDeltaX: CGFloat
    ) -> Int? {
        if let current {
            return current
        }

        guard abs(rawDeltaX) > SpaceSidebarTransitionConfig.directionLatchThreshold else {
            return nil
        }

        return rawDeltaX <= 0 ? 1 : -1
    }
}

struct SpaceSidebarTransitionState: Equatable {
    var sourceSpaceId: UUID?
    var destinationSpaceId: UUID?
    var direction: Int = 0
    var progress: Double = 0
    var latchedDirection: Int?
    var isCommitArmed = false
    var phase: SpaceSidebarTransitionPhase = .idle
    var trigger: SpaceSidebarTransitionTrigger?

    var isGestureActive: Bool {
        phase != .idle && sourceSpaceId != nil
    }

    var hasDestination: Bool {
        sourceSpaceId != nil && destinationSpaceId != nil
    }

    var visualSelectedSpaceId: UUID? {
        hasDestination ? destinationSpaceId : nil
    }

    var shouldCommitSwipeOnEnd: Bool {
        trigger == .swipe
            && isCommitArmed
            && latchedDirection != nil
            && destinationSpaceId != nil
            && progress >= SpaceSidebarTransitionConfig.swipeCommitThreshold
    }

    mutating func beginClick(
        from committedSpaceId: UUID?,
        to targetSpaceId: UUID,
        orderedSpaceIds: [UUID]
    ) -> Bool {
        guard !isGestureActive else { return false }

        let resolvedSourceSpaceId = committedSpaceId ?? orderedSpaceIds.first
        guard
            let resolvedSourceSpaceId,
            resolvedSourceSpaceId != targetSpaceId,
            let direction = Self.transitionDirection(
                from: resolvedSourceSpaceId,
                to: targetSpaceId,
                orderedSpaceIds: orderedSpaceIds
            )
        else {
            return false
        }

        sourceSpaceId = resolvedSourceSpaceId
        destinationSpaceId = targetSpaceId
        self.direction = direction
        latchedDirection = nil
        progress = 0
        isCommitArmed = true
        phase = .clickAnimating
        trigger = .click
        return true
    }

    mutating func beginSwipeGesture(
        from committedSpaceId: UUID?,
        orderedSpaceIds: [UUID]
    ) -> Bool {
        guard phase == .idle || (phase == .interactive && trigger == .swipe) else {
            return false
        }

        let resolvedSourceSpaceId = committedSpaceId ?? orderedSpaceIds.first
        guard let resolvedSourceSpaceId else {
            return false
        }

        if phase == .interactive,
           trigger == .swipe,
           sourceSpaceId == resolvedSourceSpaceId
        {
            return true
        }

        sourceSpaceId = resolvedSourceSpaceId
        destinationSpaceId = nil
        direction = 0
        latchedDirection = nil
        progress = 0
        phase = .interactive
        isCommitArmed = false
        trigger = .swipe
        return true
    }

    mutating func updateSwipeGesture(
        progress requestedProgress: Double,
        latchedDirection requestedDirection: Int?,
        orderedSpaceIds: [UUID]
    ) {
        guard isGestureActive, trigger == .swipe else { return }

        progress = min(max(requestedProgress, 0), 1)

        guard
            let sourceSpaceId,
            let sourceIndex = orderedSpaceIds.firstIndex(of: sourceSpaceId)
        else {
            reset()
            return
        }

        if let requestedDirection {
            latchedDirection = latchedDirection ?? requestedDirection
        }

        guard let resolvedDirection = latchedDirection else {
            destinationSpaceId = nil
            direction = 0
            isCommitArmed = false
            return
        }

        direction = resolvedDirection

        let destinationIndex = sourceIndex + resolvedDirection
        guard orderedSpaceIds.indices.contains(destinationIndex) else {
            destinationSpaceId = nil
            isCommitArmed = false
            return
        }

        destinationSpaceId = orderedSpaceIds[destinationIndex]
        isCommitArmed = true
    }

    mutating func updateProgress(_ value: Double) {
        guard isGestureActive else { return }
        progress = min(max(value, 0), 1)
    }

    mutating func markSettling() {
        guard isGestureActive else { return }
        phase = .settling
    }

    mutating func syncSpaces(
        orderedSpaceIds: [UUID],
        committedSpaceId: UUID?
    ) {
        guard !orderedSpaceIds.isEmpty else {
            reset()
            return
        }

        guard isGestureActive else { return }
        guard let sourceSpaceId else {
            reset()
            return
        }

        guard orderedSpaceIds.contains(sourceSpaceId) else {
            reset()
            return
        }

        if let destinationSpaceId,
           !orderedSpaceIds.contains(destinationSpaceId) {
            reset()
            return
        }

        if trigger == .swipe,
           phase == .interactive,
           let committedSpaceId,
           committedSpaceId != sourceSpaceId
        {
            reset()
            return
        }

        if let destinationSpaceId,
           Self.transitionDirection(
               from: sourceSpaceId,
               to: destinationSpaceId,
               orderedSpaceIds: orderedSpaceIds
           ) == nil {
            reset()
        }
    }

    mutating func finishTransition(commit: Bool) -> UUID? {
        guard isGestureActive else { return nil }
        let resolvedDestinationSpaceId = commit ? destinationSpaceId : nil
        reset()
        return resolvedDestinationSpaceId
    }

    mutating func reset() {
        sourceSpaceId = nil
        destinationSpaceId = nil
        direction = 0
        latchedDirection = nil
        progress = 0
        isCommitArmed = false
        phase = .idle
        trigger = nil
    }

    static func transitionDirection(
        from sourceSpaceId: UUID,
        to destinationSpaceId: UUID,
        orderedSpaceIds: [UUID]
    ) -> Int? {
        guard
            let sourceIndex = orderedSpaceIds.firstIndex(of: sourceSpaceId),
            let destinationIndex = orderedSpaceIds.firstIndex(of: destinationSpaceId),
            sourceIndex != destinationIndex
        else {
            return nil
        }

        return destinationIndex > sourceIndex ? 1 : -1
    }
}
