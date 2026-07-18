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
        _ shortcutState: RecentlyClosedShortcutLiveState,
        in windowState: BrowserWindowState? = nil
    ) -> Bool {
        liveInstances.restore(
            shortcutState,
            preferredWindow: windowState
        )
    }

    func restoreLauncher(
        from pinState: RecentlyClosedShortcutPinState,
        in windowState: BrowserWindowState? = nil
    ) -> Bool {
        launchers.restore(pinState, fallbackWindow: windowState) != nil
    }
}
