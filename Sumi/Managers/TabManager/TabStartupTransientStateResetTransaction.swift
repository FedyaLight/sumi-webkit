import Foundation

@MainActor
final class TabStartupTransientStateResetTransaction {
    private let liveShortcutRetirement: LiveShortcutTabBatchRetirement

    init(
        liveShortcutRetirement: LiveShortcutTabBatchRetirement
    ) {
        self.liveShortcutRetirement = liveShortcutRetirement
    }

    func reset() {
        _ = liveShortcutRetirement.removeAll()
    }
}
