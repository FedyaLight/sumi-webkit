@MainActor
struct ShortcutSplitLauncherCatalogInsertionPlan {
    let insertedPin: ShortcutPin
    let sourceCatalog: ShortcutSplitLauncherCatalogSnapshot
    let insertion: ShortcutSplitLauncherCatalogMovePlan.Insertion
    let presentationPreview: ShortcutPresentationCatalogInsertionPreview
}
