import Foundation

@MainActor
struct PreparedDetachedTabShortcutTransition {
    let windows: ShortcutTabBindingWindowContribution
    let runtime: DetachedTabRuntimeRetirementParticipant
}
