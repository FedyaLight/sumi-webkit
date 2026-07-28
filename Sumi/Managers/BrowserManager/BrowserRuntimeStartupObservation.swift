import Combine
import Foundation

@MainActor
final class BrowserRuntimeStartupObservation {
    private let tabStructureEvents: TabStructureEventBus
    private let windows: WindowRegistry
    private let windowRestore: WindowSessionRestoreService
    private let windowRestoration: BrowserWindowSessionRestorationService
    private let windowActivation: BrowserWindowActivationService
    private let liveFolders: SumiLiveFolderManager
    private let liveFoldersModule: SumiLiveFoldersModule
    private let startupReconciliation:
        BrowserStartupSessionReconciliationService
    private let protectionRestore: BrowserStartupProtectionRuntime
    private var initialDataLoadedCancellable: AnyCancellable?

    init(
        tabStructureEvents: TabStructureEventBus,
        windows: WindowRegistry,
        windowRestore: WindowSessionRestoreService,
        windowRestoration: BrowserWindowSessionRestorationService,
        windowActivation: BrowserWindowActivationService,
        liveFolders: SumiLiveFolderManager,
        liveFoldersModule: SumiLiveFoldersModule,
        startupReconciliation: BrowserStartupSessionReconciliationService,
        protectionRestore: BrowserStartupProtectionRuntime
    ) {
        self.tabStructureEvents = tabStructureEvents
        self.windows = windows
        self.windowRestore = windowRestore
        self.windowRestoration = windowRestoration
        self.windowActivation = windowActivation
        self.liveFolders = liveFolders
        self.liveFoldersModule = liveFoldersModule
        self.startupReconciliation = startupReconciliation
        self.protectionRestore = protectionRestore
    }

    func start() {
        initialDataLoadedCancellable = tabStructureEvents
            .initialDataLoadedPublisher
            .sink { [weak self] in
                self?.settleInitialData()
            }
        protectionRestore.beginProtectionRestoreForStartupIfNeeded()
    }

    func cancel() {
        initialDataLoadedCancellable?.cancel()
        initialDataLoadedCancellable = nil
        protectionRestore.cancelProtectionRestoreTask()
    }

    private func settleInitialData() {
        let registeredWindows = windows.allWindows
        windowRestore.handleTabManagerDataLoaded(windows: registeredWindows)
        windowRestoration.completePendingRegistrations(
            registeredWindows: registeredWindows
        )
        windowActivation.completeDeferredActivation(
            for: windows.activeWindow
        )
        liveFolders.startAfterTabRestore(
            isEnabled: liveFoldersModule.isEnabled
        )
        startupReconciliation.reconcileIfReady()
    }
}
