import Foundation

@MainActor
final class BrowserTabRuntimeReconcileOwner {
    private let tabSuspension: TabSuspensionController
    private let backgroundMedia: SumiBackgroundMediaOptimizationService

    init(
        tabSuspension: TabSuspensionController,
        backgroundMedia: SumiBackgroundMediaOptimizationService
    ) {
        self.tabSuspension = tabSuspension
        self.backgroundMedia = backgroundMedia
    }

    func schedule(reason: String) {
        tabSuspension.scheduleReconciliation(reason: reason)
        backgroundMedia.scheduleReconcile(reason: reason)
    }
}
