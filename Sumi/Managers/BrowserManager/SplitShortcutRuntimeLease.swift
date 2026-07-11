/// Synchronous operation-scoped access to the tab runtime. Services retain
/// only a provider, so late calls after browser teardown become no-ops.
@MainActor
struct SplitShortcutRuntimeLease {
    let tabManager: TabManager
}
