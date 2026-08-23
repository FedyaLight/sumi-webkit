@testable import Sumi

@MainActor
final class TestShortcutSplitLauncherMoveBatchPreparer:
    ShortcutSplitLauncherMoveBatchPreparing {
    private let acceptsAction: @MainActor (
        ShortcutPin,
        ShortcutSplitLauncherDestination
    ) -> Bool
    private let prepareAction: @MainActor (
        [PreparedShortcutSplitLauncherMove]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?
    private let preflightContributionAction: @MainActor (
        [PreparedShortcutSplitLauncherMove]
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
            [PreparedShortcutSplitLauncherMove]
        ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?,
        preflightBindingContribution: @escaping @MainActor (
            [PreparedShortcutSplitLauncherMove]
        ) -> ShortcutSplitLauncherBindingPreflight?,
        prepareBindingContributionPlan: @escaping @MainActor (
            ShortcutSplitLauncherBindingPreflight,
            ShortcutSplitLauncherCatalogInsertionPlan
        ) -> ShortcutSplitLauncherBindingContribution?
    ) {
        acceptsAction = accepts
        prepareAction = prepare
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
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        prepareAction(preparedMoves)
    }

    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        preflightContributionAction(preparedMoves)
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
    ShortcutSplitLauncherMoveBatchParticipant {
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
}
