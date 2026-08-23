import Foundation
import SumiDomain

@MainActor
final class WindowSplitPresentationPreparationService {
    private let drafts: WindowSplitPresentationDraftPlanner
    private let activation: ShortcutPresentationActivationService
    private let regularTabs: RegularTabCollectionOwner
    private let validator: WindowSplitPresentationSettlementValidator
    private let windows: @MainActor () -> [BrowserWindowState]

    init(
        drafts: WindowSplitPresentationDraftPlanner,
        activation: ShortcutPresentationActivationService,
        regularTabs: RegularTabCollectionOwner,
        validator: WindowSplitPresentationSettlementValidator,
        windows: @escaping @MainActor () -> [BrowserWindowState]
    ) {
        self.drafts = drafts
        self.activation = activation
        self.regularTabs = regularTabs
        self.validator = validator
        self.windows = windows
    }

    func prepare(
        input: WindowSplitPresentationSettlementInput,
        currentGroups: [SumiDomain.SplitGroup],
        activationSource: WindowSplitPresentationActivationSource,
        terminalEffects: WindowSplitPresentationEffectExecutor
    ) -> PreparedWindowSplitPresentationSettlement? {
        guard let draft = drafts.prepare(
            input,
            currentGroups: currentGroups,
            windows: windows()
        ), let residences = WindowSplitPresentationResidencePreparer().prepare(
            source: activationSource,
            requests: draft.activationRequests,
            activation: activation
        ), let plan = WindowSplitPresentationSettlementPlanner().prepare(
            draft,
            shortcutWitnesses: residences.shortcutWitnesses,
            regularTabs: regularTabs
        ) else { return nil }
        return PreparedWindowSplitPresentationSettlement(
            plan: plan,
            residences: residences,
            validator: validator,
            terminalEffects: terminalEffects
        )
    }

    func currentWindows() -> [BrowserWindowState] {
        windows()
    }
}
