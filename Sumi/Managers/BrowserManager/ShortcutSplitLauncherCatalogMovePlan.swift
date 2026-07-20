import Foundation

@MainActor
struct ShortcutSplitLauncherCatalogMovePlan {
    struct Insertion {
        let pin: ShortcutPin
        let index: Int
        let sidebarVisualMembership: ShortcutPinSidebarVisualMembership
        let target: ShortcutSplitLauncherBindingPinTarget
    }

    struct Entry {
        let pinID: UUID
        let destination: ShortcutSplitLauncherDestination
        let target: ShortcutSplitLauncherBindingPinTarget
    }

    let insertion: Insertion?
    let entries: [Entry]
}

enum ShortcutSplitLauncherCatalogStageOutcome {
    case staged
    case requiresStructuralRollback
}
