import SumiDomain

@MainActor
protocol SplitDropPresentationReconciling: AnyObject {
    func reconcile(_ effect: SplitDropCommitEffect)
    func prepare(
        _ effect: SplitDropCommitEffect,
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        requiredWindow: BrowserWindowState,
        insertionPreview: ShortcutPresentationCatalogInsertionPreview,
        residenceContribution: DisplayedShortcutResidenceContribution
    ) -> PreparedWindowSplitPresentationSettlement?
}

extension WindowSplitPresentationSynchronizer: SplitDropPresentationReconciling {
    func prepare(
        _ effect: SplitDropCommitEffect,
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        requiredWindow: BrowserWindowState,
        insertionPreview: ShortcutPresentationCatalogInsertionPreview,
        residenceContribution: DisplayedShortcutResidenceContribution
    ) -> PreparedWindowSplitPresentationSettlement? {
        guard let projection = splitDropPresentationProjection(
            effect,
            caller: requiredWindow
        ) else { return nil }
        return prepareSettlementAgainstSource(
            previousGroups: effect.previousGroups,
            sourceGroups: sourceGroups,
            replacementGroups: replacementGroups,
            affectedGroupIDs: effect.affectedGroupIDs,
            preferredSelections: projection.preferredSelections,
            insertionPreview: insertionPreview,
            residenceContribution: residenceContribution,
            requiredWindows: projection.requiredWindows
        )
    }

    func reconcile(_ effect: SplitDropCommitEffect) {
        synchronize(
            previousGroups: effect.previousGroups,
            affectedGroupIDs: effect.affectedGroupIDs,
            preferredSelections: [
                effect.callerWindowID: WindowSplitSelection(
                    groupID: effect.targetGroupID,
                    activeMemberID: effect.preferredActiveMemberID
                ),
            ]
        )
    }
}

@MainActor
struct SplitDropPresentationSelectionProjection {
    let preferredSelections: [UUID: WindowSplitSelection]
    let requiredWindows: [UUID: BrowserWindowState]
}

@MainActor
enum SplitDropPresentationSelectionProjector {
    static func prepare(
        _ effect: SplitDropCommitEffect,
        caller: BrowserWindowState,
        windows: [BrowserWindowState]
    ) -> SplitDropPresentationSelectionProjection? {
        guard Set(windows.map(\.id)).count == windows.count,
              windows.first(where: {
                  $0.id == effect.callerWindowID
              }) === caller else { return nil }
        let selection = WindowSplitSelection(
            groupID: effect.targetGroupID,
            activeMemberID: effect.preferredActiveMemberID
        )
        var preferred = [effect.callerWindowID: selection]
        var required = [effect.callerWindowID: caller]
        if let sourceGroupID = effect.sourceGroupID {
            for window in windows where window.id != caller.id
                && window.splitSelection?.groupID == sourceGroupID
                && window.splitSelection?.activeMemberID
                    == effect.movingMemberID {
                preferred[window.id] = selection
                required[window.id] = window
            }
        }
        return SplitDropPresentationSelectionProjection(
            preferredSelections: preferred,
            requiredWindows: required
        )
    }
}

@MainActor
final class RegularTabShortcutSplitPresentationPreparation {
    private let presentations: any SplitDropPresentationReconciling
    private let effect: SplitDropCommitEffect
    private let sourceGroups: [SumiDomain.SplitGroup]
    private let replacementGroups: [SumiDomain.SplitGroup]
    private let requiredWindow: BrowserWindowState

    init(
        presentations: any SplitDropPresentationReconciling,
        effect: SplitDropCommitEffect,
        sourceGroups: [SumiDomain.SplitGroup],
        replacementGroups: [SumiDomain.SplitGroup],
        requiredWindow: BrowserWindowState
    ) {
        self.presentations = presentations
        self.effect = effect
        self.sourceGroups = sourceGroups
        self.replacementGroups = replacementGroups
        self.requiredWindow = requiredWindow
    }

    func prepare(
        for insertion: ShortcutSplitLauncherCatalogInsertionPlan,
        residenceContribution: DisplayedShortcutResidenceContribution
    ) -> PreparedWindowSplitPresentationSettlement? {
        presentations.prepare(
            effect,
            sourceGroups: sourceGroups,
            replacementGroups: replacementGroups,
            requiredWindow: requiredWindow,
            insertionPreview: insertion.presentationPreview,
            residenceContribution: residenceContribution
        )
    }
}
