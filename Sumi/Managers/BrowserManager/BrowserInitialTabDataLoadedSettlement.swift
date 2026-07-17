import Foundation

@MainActor
final class BrowserInitialTabDataLoadedSettlement {
    private let windows: BrowserInitialWindowDataSettlement
    private let liveFolders: SumiLiveFolderManager
    private let liveFoldersModule: SumiLiveFoldersModule
    private let startupReconciliation: BrowserStartupSessionReconciliationService

    init(
        windows: BrowserInitialWindowDataSettlement,
        liveFolders: SumiLiveFolderManager,
        liveFoldersModule: SumiLiveFoldersModule,
        startupReconciliation: BrowserStartupSessionReconciliationService
    ) {
        self.windows = windows
        self.liveFolders = liveFolders
        self.liveFoldersModule = liveFoldersModule
        self.startupReconciliation = startupReconciliation
    }

    func settle() {
        windows.settle()
        liveFolders.startAfterTabRestore(
            isEnabled: liveFoldersModule.isEnabled
        )
        startupReconciliation.reconcileIfReady()
    }
}
