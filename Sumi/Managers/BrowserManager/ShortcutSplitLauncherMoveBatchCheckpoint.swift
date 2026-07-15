@MainActor
final class ShortcutSplitLauncherMoveBatchCheckpoint {
    private enum State {
        case prepared, awaitingStructuralRollback, terminal
        case staged(ShortcutSplitLauncherCatalogSnapshot)
        case published(ShortcutSplitLauncherCatalogSnapshot)
    }

    private let catalog: ShortcutSplitLauncherCatalogTransaction
    let source: ShortcutSplitLauncherCatalogSnapshot
    let plan: ShortcutSplitLauncherCatalogMovePlan
    private var state = State.prepared

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        source: ShortcutSplitLauncherCatalogSnapshot,
        plan: ShortcutSplitLauncherCatalogMovePlan
    ) {
        self.catalog = catalog
        self.source = source
        self.plan = plan
    }

    func validateForStaging() -> Bool {
        if case .prepared = state { return catalog.matches(source) }
        return false
    }

    func stage() -> ShortcutSplitLauncherCatalogStageOutcome {
        guard validateForStaging() else {
            state = .awaitingStructuralRollback
            return .requiresStructuralRollback
        }
        if let insertion = plan.insertion {
            guard let inserted = catalog.stageInsertion(insertion),
                  insertion.target.accepts(inserted) else {
                state = .awaitingStructuralRollback
                return .requiresStructuralRollback
            }
        }
        for entry in plan.entries {
            guard let pin = catalog.currentPin(withID: entry.pinID),
                  catalog.move(
                      pin,
                      destination: entry.destination,
                      applying: entry.target.accepts
                  ) != nil else {
                state = .awaitingStructuralRollback
                return .requiresStructuralRollback
            }
        }
        state = .staged(catalog.snapshot())
        return .staged
    }

    func isCurrent() -> Bool {
        switch state {
        case .staged(let expected), .published(let expected):
            return catalog.matches(expected)
        case .prepared, .awaitingStructuralRollback, .terminal:
            return false
        }
    }

    func confirmStructuralRollback() -> Bool {
        switch state {
        case .awaitingStructuralRollback, .staged:
            guard catalog.matches(source) else { return false }
            state = .terminal
            return true
        case .prepared, .published, .terminal:
            return false
        }
    }

    func requireCurrentForPublication() {
        guard case .staged(let expected) = state,
              catalog.matches(expected) else {
            preconditionFailure("Launcher catalog changed before publication")
        }
        state = .published(expected)
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .terminal
        return true
    }

    func abandonForTerminalDrain() {
        precondition(isCurrent())
        state = .terminal
    }
}
