import Foundation

@MainActor
final class TabStartupTransientStateResetTransaction {
    private let lazyRestore: TabLazyRestoreCoordinator
    private let liveShortcutRetirement: LiveShortcutTabBatchRetirement

    init(
        lazyRestore: TabLazyRestoreCoordinator,
        liveShortcutRetirement: LiveShortcutTabBatchRetirement
    ) {
        self.lazyRestore = lazyRestore
        self.liveShortcutRetirement = liveShortcutRetirement
    }

    func reset() {
        lazyRestore.clear()
        _ = liveShortcutRetirement.removeAll()
    }
}
