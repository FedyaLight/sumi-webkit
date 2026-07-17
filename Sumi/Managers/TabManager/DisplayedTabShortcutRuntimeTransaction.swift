import Foundation

@MainActor
final class DisplayedTabShortcutRuntimeTransaction {
    let windows: ShortcutTabBindingWindowContribution
    private let sourceModel: DisplayedTabShortcutSourceModelTransaction
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeAttachment: TabRuntimeAttachmentWitness

    init(
        windows: ShortcutTabBindingWindowContribution,
        sourceModel: DisplayedTabShortcutSourceModelTransaction,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeAttachment: TabRuntimeAttachmentWitness
    ) {
        self.windows = windows
        self.sourceModel = sourceModel
        self.structuralLookup = structuralLookup
        self.runtimeAttachment = runtimeAttachment
    }

    func validateForStaging() -> Bool {
        runtimeAttachment.isCurrent() && sourceModel.validateForStaging()
    }

    func stage() -> Bool {
        guard validateForStaging(), sourceModel.stage() else { return false }
        return runtimeAttachment.isCurrent()
            && sourceModel.stagedSourceRemovalIsExact()
    }

    func stagedModelIsExact() -> Bool {
        runtimeAttachment.isCurrent() && sourceModel.stagedModelIsExact()
    }

    func rollback() -> Bool { sourceModel.rollback() }

    func cancelPrepared() -> Bool { sourceModel.cancelPrepared() }

    func settleAfterFailedStage() -> Bool {
        sourceModel.settleAfterFailedStage()
    }

    func abandonForTerminalDrain() {
        sourceModel.abandonForTerminalDrain()
    }

    func canAbandonForTerminalDrain() -> Bool {
        sourceModel.canAbandonForTerminalDrain()
    }

    func publishBeforeBinding() {
        sourceModel.publishBeforeBinding()
    }

    func publishAfterBinding() {
        sourceModel.finishPublication()
        let attachment = runtimeAttachment
        let freshTabs = sourceModel.freshTabs
        structuralLookup.runAfterCurrentBatch {
            guard let runtime = attachment.currentRegistry() else { return }
            freshTabs.forEach {
                runtime.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(
                    $0.0,
                    in: $0.1
                )
            }
        }
    }
}
