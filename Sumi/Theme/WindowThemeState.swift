import Foundation

struct SpaceTransitionIdentity: Equatable, Hashable {
    let id: UUID
    let sourceSpaceId: UUID
    let destinationSpaceId: UUID

    init(
        id: UUID = UUID(),
        sourceSpaceId: UUID,
        destinationSpaceId: UUID
    ) {
        self.id = id
        self.sourceSpaceId = sourceSpaceId
        self.destinationSpaceId = destinationSpaceId
    }
}

enum WindowThemeTransitionMode: Equatable {
    case idle
    case programmatic
    case interactive
}

struct WindowThemeState: Equatable {
    var committedTheme: WorkspaceTheme = .default
    var sourceTheme: WorkspaceTheme?
    var targetTheme: WorkspaceTheme?
    var progress: Double = 1.0
    var mode: WindowThemeTransitionMode = .idle
    var token: UUID?
    var sourceSpaceId: UUID?
    var destinationSpaceId: UUID?
    var interactiveSpaceTransitionIdentity: SpaceTransitionIdentity?

    var isTransitioning: Bool {
        mode != .idle && sourceTheme != nil && targetTheme != nil
    }

    var isInteractive: Bool {
        mode == .interactive
    }

    var resolvedTheme: WorkspaceTheme {
        guard isTransitioning,
              let sourceTheme,
              let targetTheme
        else {
            return committedTheme
        }

        return sourceTheme.interpolated(
            to: targetTheme,
            progress: progress
        )
    }

    mutating func restore(_ theme: WorkspaceTheme) {
        committedTheme = theme
        sourceTheme = nil
        targetTheme = theme
        progress = 1.0
        mode = .idle
        token = nil
        sourceSpaceId = nil
        destinationSpaceId = nil
        interactiveSpaceTransitionIdentity = nil
    }

    mutating func beginProgrammatic(
        from currentTheme: WorkspaceTheme,
        to nextTheme: WorkspaceTheme,
        token: UUID
    ) {
        committedTheme = currentTheme
        sourceTheme = currentTheme
        targetTheme = nextTheme
        progress = 0.0
        mode = .programmatic
        self.token = token
        sourceSpaceId = nil
        destinationSpaceId = nil
        interactiveSpaceTransitionIdentity = nil
    }

    @discardableResult
    mutating func beginInteractive(
        sourceSpaceId: UUID,
        destinationSpaceId: UUID,
        from sourceTheme: WorkspaceTheme,
        to destinationTheme: WorkspaceTheme,
        initialProgress: Double
    ) -> SpaceTransitionIdentity {
        beginInteractive(
            identity: SpaceTransitionIdentity(
                sourceSpaceId: sourceSpaceId,
                destinationSpaceId: destinationSpaceId
            ),
            from: sourceTheme,
            to: destinationTheme,
            initialProgress: initialProgress
        )
    }

    @discardableResult
    mutating func beginInteractive(
        identity: SpaceTransitionIdentity,
        from sourceTheme: WorkspaceTheme,
        to destinationTheme: WorkspaceTheme,
        initialProgress: Double
    ) -> SpaceTransitionIdentity {
        committedTheme = sourceTheme
        self.sourceTheme = sourceTheme
        targetTheme = destinationTheme
        progress = min(max(initialProgress, 0.0), 1.0)
        mode = .interactive
        token = identity.id
        sourceSpaceId = identity.sourceSpaceId
        destinationSpaceId = identity.destinationSpaceId
        interactiveSpaceTransitionIdentity = identity
        return identity
    }

    mutating func updateProgress(_ progress: Double) {
        self.progress = min(max(progress, 0.0), 1.0)
    }

    mutating func cancel() {
        restore(sourceTheme ?? committedTheme)
    }

    func matchesInteractiveSpaceTransition(_ identity: SpaceTransitionIdentity?) -> Bool {
        guard isInteractive else { return false }
        guard let currentIdentity = interactiveSpaceTransitionIdentity else {
            return identity == nil
        }
        return currentIdentity == identity
    }
}
