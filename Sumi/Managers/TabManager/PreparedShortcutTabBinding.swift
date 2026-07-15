@MainActor
struct PreparedShortcutTabBinding {
    let receipt: ShortcutSplitLauncherTabReceipt
    let target: ShortcutSplitLauncherBindingTarget
    let profile: ShortcutTabProfileAssignmentAdmission
}

struct PreparedShortcutTabRuntimeBinding {
    let plan: ShortcutSplitLauncherBindingPlan
    let profile: ShortcutTabProfileAssignmentAdmission
}
