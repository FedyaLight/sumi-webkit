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

    convenience init(tabManager: TabManager) {
        let targets = ShortcutTabBindingTargetMutationService(
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            profiles: tabManager.profileAssignments.tabs
        )
        self.init(
            presentationRefreshes: tabManager.liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: tabManager.liveShortcutTabs,
                targets: targets,
                runtimeConnection: tabManager.runtimePortConnection,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            targets: targets
        )
    }

    func refreshAdmission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        presentationRefreshes.admission(for: pin)
    }

    @discardableResult
    func refreshInstances(
        for pin: ShortcutPin,
        admission: LiveShortcutPresentationRefreshAdmission? = nil
    ) -> Bool {
        guard let admission = admission
            ?? presentationRefreshes.admission(for: pin) else {
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
