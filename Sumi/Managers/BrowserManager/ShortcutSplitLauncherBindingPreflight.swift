@MainActor
final class ShortcutSplitLauncherBindingPreflight {
    struct Entry {
        let restoration: PreparedShortcutSplitLauncherRestoration
        let binding: ShortcutSplitLauncherPreparedBinding
    }

    let catalog: ShortcutSplitLauncherCatalogTransaction
    let bindingBatch: ShortcutSplitLauncherBindingBatchStaging
    let entries: [Entry]

    var builder: ShortcutTabBindingBatchBuilder { bindingBatch.builder }

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        bindingBatch: ShortcutSplitLauncherBindingBatchStaging,
        entries: [Entry]
    ) {
        self.catalog = catalog
        self.bindingBatch = bindingBatch
        self.entries = entries
    }
}
