import Foundation

/// Coordinates the settings-attachment workflow: when a `SumiSettingsService`
/// is (re)attached to the browser, every runtime subsystem that consumes
/// settings is reconfigured in one place — downloads, tab-suspension policy,
/// startup-session policy, and automatic data cleanup.
///
/// Every collaborator is a concrete settings-consuming capability; none of
/// them knows the browser hub.
@MainActor
final class BrowserSettingsAttachmentCoordinator {
    private let settingsState: BrowserSettingsState
    private let downloadManager: DownloadManager
    private let tabSuspension: TabSuspensionController
    private let startupReconciliation: BrowserStartupSessionReconciliationService
    private let automaticDataCleanup: BrowserAutomaticBrowsingDataCleanup
    private weak var attachedSettings: SumiSettingsService?

    init(
        settingsState: BrowserSettingsState,
        downloadManager: DownloadManager,
        tabSuspension: TabSuspensionController,
        startupReconciliation: BrowserStartupSessionReconciliationService,
        automaticDataCleanup: BrowserAutomaticBrowsingDataCleanup
    ) {
        self.settingsState = settingsState
        self.downloadManager = downloadManager
        self.tabSuspension = tabSuspension
        self.startupReconciliation = startupReconciliation
        self.automaticDataCleanup = automaticDataCleanup
    }

    var settings: SumiSettingsService? {
        settingsState.settings
    }

    func attach(_ settings: SumiSettingsService?) {
        attachedSettings?.setTabSuspensionPolicyChangedHandler(nil)
        attachedSettings = settings
        settingsState.update(settings)
        downloadManager.settings = settings
        // Weak capture keeps the policy source tracking the live settings
        // object without retaining it past its owner.
        tabSuspension.configurePolicy { [weak settings] in
            TabSuspensionPolicy(settings: settings)
        }
        settings?.setTabSuspensionPolicyChangedHandler {
            [weak tabSuspension] in
            tabSuspension?.policyDidChange(reason: "settings-policy-changed")
        }
        startupReconciliation.reconcileIfReady()
        automaticDataCleanup.schedule(reason: "settings-attached")
    }
}
