import Foundation
import SumiDomain

/// Replaces a regular tab that is not displayed by any browser window with a
/// durable shortcut definition. It deliberately creates no live shortcut tab;
/// a window materializes one later when the launcher is activated.
@MainActor
final class DetachedTabShortcutConverter {
    private let batches: ShortcutTabBindingBatchFactory
    private let source: DetachedTabShortcutSourcePreparer
    private let windowReconciler: RegularTabShortcutWindowReconciler

    init(
        batches: ShortcutTabBindingBatchFactory,
        source: DetachedTabShortcutSourcePreparer,
        windowReconciler: RegularTabShortcutWindowReconciler
    ) {
        self.batches = batches
        self.source = source
        self.windowReconciler = windowReconciler
    }

    func beginBindingBatch(
        using attachment: TabRuntimeAttachmentWitness
    ) -> ShortcutTabBindingBatchBuilder {
        batches.make(using: attachment)
    }

    func prepare(
        transition: RegularTabShortcutWindowTransitionPlan,
        using authorization: AuthorizedDetachedTabShortcutConversion
    ) -> PreparedDetachedTabShortcutTransition? {
        guard let runtime = source.prepare(using: authorization) else {
            return nil
        }
        let windows = authorization.runtime.flatMap {
            windowReconciler.prepareContribution(
                originalTabId: authorization.tab.id,
                splitTransition: transition,
                sourceSpaceId: authorization.tab.spaceId,
                liveTabsByWindowId: [:],
                terminalIdentitiesByWindowId: [:],
                selectedWindowIds: [],
                using: $0
            )
        } ?? .empty
        return PreparedDetachedTabShortcutTransition(
            windows: windows,
            runtime: runtime
        )
    }
}
