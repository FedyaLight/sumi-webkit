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
        [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?

    init(
        accepts: @escaping @MainActor (
            ShortcutPin,
            ShortcutSplitLauncherDestination
        ) -> Bool,
        prepare: @escaping @MainActor (
            [PreparedShortcutSplitLauncherRestoration]
        ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?,
        prepareForComposedResidenceAggregate: @escaping @MainActor (
            [PreparedShortcutSplitLauncherRestoration]
        ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?
    ) {
        acceptsAction = accepts
        prepareAction = prepare
        prepareComposedAction = prepareForComposedResidenceAggregate
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
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)? {
        prepareComposedAction(restorations)
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
    func canRollback() -> Bool { current() }
    func rollback() -> Bool { rollbackAction() }
    func settleAdmittedModel() { settleAction() }
    func publishAndExecute() { publishAction() }
}
