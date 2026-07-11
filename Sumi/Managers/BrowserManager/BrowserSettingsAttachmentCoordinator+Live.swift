import Foundation

extension BrowserSettingsAttachmentCoordinator {
    /// Composes the settings-attachment workflow against the live
    /// settings-consuming subsystems. Only the settings attachment point
    /// (`BrowserManager.sumiSettings.didSet`) builds and holds the result.
    @MainActor
    static func live(browserManager: BrowserManager) -> BrowserSettingsAttachmentCoordinator {
        BrowserSettingsAttachmentCoordinator(
            downloadManager: browserManager.downloadManager,
            tabSuspension: browserManager.tabSuspensionController,
            backgroundMedia: browserManager.backgroundMediaOptimizationService,
            reconcileStartupSession: { [weak browserManager] in
                browserManager?.reconcileStartupSessionIfPossible()
            },
            automaticDataCleanup: browserManager.privacyBundle.automaticDataCleanupOwner
        )
    }
}
