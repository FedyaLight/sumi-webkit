import Foundation

/// Coordinates the settings-attachment workflow: when a `SumiSettingsService`
/// is (re)attached to the browser, every runtime subsystem that consumes
/// settings is reconfigured in one place — downloads, tab-suspension policy,
/// background media, startup-session policy, and automatic data cleanup.
///
/// Every collaborator is a concrete settings-consuming capability; none of
/// them knows the browser hub.
@MainActor
final class BrowserSettingsAttachmentCoordinator {
    private let downloadManager: DownloadManager
    private let tabSuspension: TabSuspensionController
    private let backgroundMedia: SumiBackgroundMediaOptimizationService
    private let reconcileStartupSession: @MainActor () -> Void
    private let automaticDataCleanup: BrowserAutomaticDataCleanupOwner

    init(
        downloadManager: DownloadManager,
        tabSuspension: TabSuspensionController,
        backgroundMedia: SumiBackgroundMediaOptimizationService,
        reconcileStartupSession: @escaping @MainActor () -> Void,
        automaticDataCleanup: BrowserAutomaticDataCleanupOwner
    ) {
        self.downloadManager = downloadManager
        self.tabSuspension = tabSuspension
        self.backgroundMedia = backgroundMedia
        self.reconcileStartupSession = reconcileStartupSession
        self.automaticDataCleanup = automaticDataCleanup
    }

    func attach(_ settings: SumiSettingsService?) {
        downloadManager.settings = settings
        // Weak capture keeps the policy source tracking the live settings
        // object without retaining it past its owner.
        tabSuspension.configurePolicy { [weak settings] in
            TabSuspensionPolicy(settings: settings)
        }
        backgroundMedia.scheduleReconcile(reason: "settings-attached")
        reconcileStartupSession()
        automaticDataCleanup.scheduleAutomaticBrowsingDataCleanup(
            reason: "settings-attached"
        )
    }
}
