import Foundation

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
    }

    mutating func beginInteractive(
        sourceSpaceId: UUID,
        destinationSpaceId: UUID,
        from sourceTheme: WorkspaceTheme,
        to destinationTheme: WorkspaceTheme,
        initialProgress: Double
    ) {
        committedTheme = sourceTheme
        self.sourceTheme = sourceTheme
        targetTheme = destinationTheme
        progress = min(max(initialProgress, 0.0), 1.0)
        mode = .interactive
        token = UUID()
        self.sourceSpaceId = sourceSpaceId
        self.destinationSpaceId = destinationSpaceId
    }

    mutating func updateProgress(_ progress: Double) {
        self.progress = min(max(progress, 0.0), 1.0)
    }

    mutating func commit(_ theme: WorkspaceTheme) {
        restore(theme)
    }

    mutating func cancel() {
        restore(sourceTheme ?? committedTheme)
    }
}
