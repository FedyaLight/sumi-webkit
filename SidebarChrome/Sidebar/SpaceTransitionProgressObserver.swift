import SwiftUI

/// Bridges SwiftUI's interpolated animation frames back into the sidebar so
/// click and release settle can keep theme progress in sync with page motion.
/// Interactive swipe updates bypass this observer and push progress directly.
struct SpaceTransitionProgressObserver: @MainActor AnimatableModifier {
    var progress: Double
    let transitionIdentity: SpaceTransitionIdentity?
    let onChange: (Double, SpaceTransitionIdentity?) -> Void

    var animatableData: Double {
        get { progress }
        set {
            progress = newValue
            let callback = onChange
            let transitionIdentity = transitionIdentity
            DispatchQueue.main.async {
                callback(newValue, transitionIdentity)
            }
        }
    }

    func body(content: Content) -> some View {
        content
    }
}
