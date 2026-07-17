import Foundation

/// Coordinates shortcut-presentation admission with concrete target and
/// residence/window transaction participants.
@MainActor
final class ShortcutTabBindingSynchronizer {
    private let presentationRefreshes: LiveShortcutPresentationRefreshService
    private let runtimeMutations: ShortcutTabBindingRuntimeMutation
    private let targets: ShortcutTabBindingTargetMutationService

    init(
        presentationRefreshes: LiveShortcutPresentationRefreshService,
        runtimeMutations: ShortcutTabBindingRuntimeMutation,
        targets: ShortcutTabBindingTargetMutationService
    ) {
        self.presentationRefreshes = presentationRefreshes
        self.runtimeMutations = runtimeMutations
        self.targets = targets
    }

    func refreshAdmission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        presentationRefreshes.admission(for: pin)
    }

    @discardableResult
    func refreshInstances(
        for pin: ShortcutPin,
        presentationSpaceID: UUID? = nil,
        admission: LiveShortcutPresentationRefreshAdmission? = nil
    ) -> Bool {
        guard let admission = admission
            ?? presentationRefreshes.admission(
                for: pin,
                presentationSpaceID: presentationSpaceID
            ) else {
            return false
        }
        return runtimeMutations.refresh(
            pin,
            admission: admission,
            refreshes: presentationRefreshes
        )
    }

    func canRebind(_ tab: Tab, from sourcePin: ShortcutPin) -> Bool {
        runtimeMutations.canRebind(tab, from: sourcePin)
    }

    @discardableResult
    func rebind(
        _ tab: Tab,
        from sourcePin: ShortcutPin,
        to targetPin: ShortcutPin
    ) -> Bool {
        runtimeMutations.rebind(tab, from: sourcePin, to: targetPin)
    }

    func initializeFresh(
        _ tab: Tab,
        for pin: ShortcutPin,
        currentSpaceId: UUID?
    ) {
        targets.initializeFresh(
            tab,
            for: pin,
            currentSpaceID: currentSpaceId
        )
    }
}
