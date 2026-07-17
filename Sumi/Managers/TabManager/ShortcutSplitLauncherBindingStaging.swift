import Foundation

/// Creates batch-scoped launcher binding staging. Capturing the runtime lease
/// once prevents a multi-move batch from mixing attachment generations.
@MainActor
final class ShortcutSplitLauncherBindingStaging {
    private let refreshes: LiveShortcutPresentationRefreshService
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let batches: ShortcutTabBindingBatchFactory

    init(
        refreshes: LiveShortcutPresentationRefreshService,
        resolution: ShortcutPinRuntimeResolutionOwner,
        batches: ShortcutTabBindingBatchFactory
    ) {
        self.refreshes = refreshes
        self.resolution = resolution
        self.batches = batches
    }

    func beginBatch() -> ShortcutSplitLauncherBindingBatchStaging {
        ShortcutSplitLauncherBindingBatchStaging(
            refreshes: refreshes,
            resolution: resolution,
            builder: batches.make()
        )
    }

    func admission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        refreshes.admission(for: pin)
    }
}
