import Foundation

@MainActor
final class BrowserStartupSessionReconciliationService {
    private let startupRestore: BrowserStartupSessionRestoreOwner
    private let tabRestore: TabStartupRestoreLifecycle
    private let settings: BrowserSettingsState
    private let startupPolicy: BrowserStartupPolicy

    init(
        startupRestore: BrowserStartupSessionRestoreOwner,
        tabRestore: TabStartupRestoreLifecycle,
        settings: BrowserSettingsState,
        startupPolicy: BrowserStartupPolicy
    ) {
        self.startupRestore = startupRestore
        self.tabRestore = tabRestore
        self.settings = settings
        self.startupPolicy = startupPolicy
    }

    func reconcileIfReady() {
        startupRestore.reconcileIfReady(
            hasLoadedInitialTabData: { [tabRestore] in
                tabRestore.hasLoadedInitialData
            },
            startupMode: { [settings] in
                settings.settings?.startupMode
            },
            startupWindow: { [startupPolicy] in
                startupPolicy.startupWindow
            },
            applyStartupPolicy: { [startupPolicy] mode in
                startupPolicy.apply(mode)
            }
        )
    }
}
