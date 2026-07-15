/// Typed displayed-runtime participant for one admitted regular-tab shortcut
/// conversion. Durable split topology is owned by the enclosing commit
/// participants; this type owns only exact presentation/runtime settlement.
@MainActor
final class DisplayedTabShortcutConversionReceipt {
    private enum State {
        case prepared
        case modelSettled
    }

    private let pin: ShortcutPin
    private let transition: RegularTabShortcutWindowTransitionPlan
    private let authorization: AuthorizedDisplayedTabShortcutConversion
    private let presentations: DisplayedShortcutPresentationResidencePlan
    private let registry: LiveShortcutTabRegistry
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let committer: DisplayedTabShortcutConversionCommitter
    private var state = State.prepared

    init?(
        pin: ShortcutPin,
        transition: RegularTabShortcutWindowTransitionPlan,
        authorization: AuthorizedDisplayedTabShortcutConversion,
        presentations: DisplayedShortcutPresentationResidencePlan,
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner,
        committer: DisplayedTabShortcutConversionCommitter
    ) {
        guard presentations.acceptsCurrentResidences(
            for: pin,
            registry: registry,
            resolution: resolution
        ) else { return nil }
        self.pin = pin
        self.transition = transition
        self.authorization = authorization
        self.presentations = presentations
        self.registry = registry
        self.resolution = resolution
        self.committer = committer
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return presentations.acceptsCurrentResidences(
            for: pin,
            registry: registry,
            resolution: resolution
        )
    }

    func settleAdmittedModel() {
        guard isCurrent() else {
            preconditionFailure("Displayed shortcut presentation diverged")
        }
        committer.applyAdmitted(
            to: pin,
            transition: transition,
            using: authorization,
            presentations: presentations
        )
        state = .modelSettled
    }
}
