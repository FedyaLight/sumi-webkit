import Foundation

/// Coordinates decorative loading-wave lifecycle so chrome can cap concurrent layer animations.
@MainActor
final class LoadingWaveController {
    static let shared = LoadingWaveController()

    private(set) var activeAnimationCount = 0
    private let maximumConcurrentAnimations = 8

    private init() {}

    func shouldStartAnimation(
        reduceMotion: Bool,
        energySaverDisablesDecorativeEffects: Bool
    ) -> Bool {
        guard !reduceMotion, !energySaverDisablesDecorativeEffects else { return false }
        return activeAnimationCount < maximumConcurrentAnimations
    }

    func beginAnimation() {
        activeAnimationCount += 1
    }

    func endAnimation() {
        activeAnimationCount = max(0, activeAnimationCount - 1)
    }
}
