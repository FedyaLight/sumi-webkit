@testable import Sumi

@MainActor
final class TestShortcutSplitLauncherMoveBatchPreparer:
    ShortcutSplitLauncherMoveBatchPreparing {
    private let acceptsAction: @MainActor (
        ShortcutPin,
        ShortcutSplitLauncherDestination
    ) -> Bool
    private let prepareAction: @MainActor (
        [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?
    private let prepareComposedAction: @MainActor (
        [PreparedShortcutSplitLauncherRestoration],
        ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)?
    private let prepareContributionAction: @MainActor (
        [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingContribution?
    private let preflightContributionAction: @MainActor (
        [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingPreflight?
    private let prepareContributionAfterInsertionPlanAction: @MainActor (
        ShortcutSplitLauncherBindingPreflight,
        ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution?

    init(
        accepts: @escaping @MainActor (
            ShortcutPin,
            ShortcutSplitLauncherDestination
        ) -> Bool,
        prepare: @escaping @MainActor (
            [PreparedShortcutSplitLauncherRestoration]
        ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?,
        prepareForComposedResidenceAggregate: @escaping @MainActor (
            [PreparedShortcutSplitLauncherRestoration],
            ShortcutSplitLauncherComposedBindingMode
        ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)?,
        prepareBindingContributionForComposedResidenceAggregate:
            @escaping @MainActor (
                [PreparedShortcutSplitLauncherRestoration]
            ) -> ShortcutSplitLauncherBindingContribution?,
        preflightBindingContribution: @escaping @MainActor (
            [PreparedShortcutSplitLauncherRestoration]
        ) -> ShortcutSplitLauncherBindingPreflight?,
        prepareBindingContributionPlan: @escaping @MainActor (
            ShortcutSplitLauncherBindingPreflight,
            ShortcutSplitLauncherCatalogInsertionPlan
        ) -> ShortcutSplitLauncherBindingContribution?
    ) {
        acceptsAction = accepts
        prepareAction = prepare
        prepareComposedAction = prepareForComposedResidenceAggregate
        prepareContributionAction =
            prepareBindingContributionForComposedResidenceAggregate
        preflightContributionAction = preflightBindingContribution
        prepareContributionAfterInsertionPlanAction =
            prepareBindingContributionPlan
    }

    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        acceptsAction(pin, destination)
    }

    func prepare(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        prepareAction(restorations)
    }

    func prepareForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)? {
        prepareComposedAction(restorations, bindingMode)
    }

    func prepareBindingContributionForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingContribution? {
        prepareContributionAction(restorations)
    }

    func preflightBindingContribution(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        preflightContributionAction(restorations)
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        prepareContributionAfterInsertionPlanAction(preflight, insertion)
    }
}

@MainActor
final class TestShortcutSplitLauncherMoveBatchParticipant:
    ShortcutSplitLauncherMoveBatchParticipant,
    ShortcutSplitLauncherComposedMoveBatchParticipant {
    private let current: () -> Bool
    private let rollbackAction: () -> Bool
    private let settleAction: () -> Void
    private let publishAction: () -> Void

    init(
        isCurrent: @escaping () -> Bool,
        rollback: @escaping () -> Bool,
        settle: @escaping () -> Void,
        publish: @escaping () -> Void
    ) {
        current = isCurrent
        rollbackAction = rollback
        settleAction = settle
        publishAction = publish
    }

    func isCurrent() -> Bool { current() }
    func rollback() -> Bool { rollbackAction() }
    func settleAdmittedModel() -> Bool {
        settleAction()
        return true
    }
    func publishAdmittedModel() {}
    func commitTerminalEffects(
        openingFoldersWith _: TabFolderOpenStateService
    ) {
        publishAction()
    }

    func executeRestore(
        presentation _: PreparedWindowSplitPresentationSettlement,
        retirement _: ReversibleShortcutLiveTabRetirement?,
        topology _: SplitGroupReplacementReceipt,
        retirementService _: ShortcutLiveTabRetirementService,
        folderOpenState _: TabFolderOpenStateService
    ) -> PreparedProfileAssignmentBatchTransitionOutcome? {
        nil
    }

    func admitPresentationIdentity(
        to _: PreparedWindowSplitPresentationSettlement
    ) -> Bool { true }

    func cancelPrepared() -> Bool { rollbackAction() }
}
