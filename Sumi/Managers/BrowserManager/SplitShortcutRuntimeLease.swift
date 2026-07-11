/// A synchronous, operation-scoped view of the split runtime. Services retain
/// only a provider; a successful command keeps both managers alive until its
/// mutation and publication sequence has finished.
@MainActor
struct SplitShortcutRuntimeLease {
    let tabManager: TabManager
    let splitManager: SplitViewManager
}
