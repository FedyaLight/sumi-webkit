import Foundation

@MainActor
final class ClosedShortcutRestoreService {
    private let liveInstances: ClosedShortcutLiveRestoreTransaction
    private let launchers: ClosedShortcutLauncherRestoreTransaction

    init(
        liveInstances: ClosedShortcutLiveRestoreTransaction,
        launchers: ClosedShortcutLauncherRestoreTransaction
    ) {
        self.liveInstances = liveInstances
        self.launchers = launchers
    }

    func restoreLiveInstance(
        _ shortcutState: RecentlyClosedShortcutLiveState
    ) -> Bool {
        liveInstances.restore(shortcutState)
    }

    func restoreLauncher(
        from pinState: RecentlyClosedShortcutPinState
    ) -> Bool {
        launchers.restore(pinState, fallbackWindow: nil) != nil
    }
}
