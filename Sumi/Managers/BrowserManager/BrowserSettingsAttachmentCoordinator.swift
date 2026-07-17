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
    private let settingsState: BrowserSettingsState
    private let downloadManager: DownloadManager
    private let tabSuspension: TabSuspensionController
    private let backgroundMedia: SumiBackgroundMediaOptimizationService
    private let startupReconciliation: BrowserStartupSessionReconciliationService
    private let automaticDataCleanup: BrowserAutomaticBrowsingDataCleanup

    init(
        settingsState: BrowserSettingsState,
        downloadManager: DownloadManager,
        tabSuspension: TabSuspensionController,
        backgroundMedia: SumiBackgroundMediaOptimizationService,
        startupReconciliation: BrowserStartupSessionReconciliationService,
        automaticDataCleanup: BrowserAutomaticBrowsingDataCleanup
    ) {
        self.settingsState = settingsState
        self.downloadManager = downloadManager
        self.tabSuspension = tabSuspension
        self.backgroundMedia = backgroundMedia
        self.startupReconciliation = startupReconciliation
        self.automaticDataCleanup = automaticDataCleanup
    }

    var settings: SumiSettingsService? {
        settingsState.settings
    }

    func attach(_ settings: SumiSettingsService?) {
        settingsState.update(settings)
        downloadManager.settings = settings
        // Weak capture keeps the policy source tracking the live settings
        // object without retaining it past its owner.
        tabSuspension.configurePolicy { [weak settings] in
            TabSuspensionPolicy(settings: settings)
        }
        backgroundMedia.scheduleReconcile(reason: "settings-attached")
        startupReconciliation.reconcileIfReady()
        automaticDataCleanup.schedule(reason: "settings-attached")
    }
}
