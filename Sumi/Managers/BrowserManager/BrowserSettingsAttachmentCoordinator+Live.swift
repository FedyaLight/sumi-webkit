import Foundation

extension BrowserSettingsAttachmentCoordinator {
    /// Composes the settings-attachment workflow against the live
    /// settings-consuming subsystems. Only the settings attachment point
    /// (`BrowserManager.sumiSettings.didSet`) builds and holds the result.
    @MainActor
    static func live(browserManager: BrowserManager) -> BrowserSettingsAttachmentCoordinator {
        BrowserSettingsAttachmentCoordinator(
            settingsState: browserManager.settingsState,
            downloadManager: browserManager.downloadManager,
            tabSuspension: browserManager.tabSuspensionController,
            startupReconciliation: browserManager.startupSessionReconciliation,
            automaticDataCleanup: browserManager.privacyBundle
                .automaticBrowsingDataCleanup
        )
    }
}
