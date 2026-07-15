import Foundation

/// Adopts an already-authorized regular Tab into one exact live-shortcut
/// residence. Fresh Tab creation remains in `ShortcutTabMaterializer`.
@MainActor
final class ShortcutTabAdopter {
    private let registry: LiveShortcutTabRegistry
    private let bindings: ShortcutTabBindingSynchronizer
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        registry: LiveShortcutTabRegistry,
        bindings: ShortcutTabBindingSynchronizer,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.registry = registry
        self.bindings = bindings
        self.membership = membership
        self.structuralLookup = structuralLookup
    }

    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            bindings: tabManager.shortcutTabBindings,
            membership: tabManager.tabCollectionMembershipOwner,
            structuralLookup: tabManager.structuralLookupCoordinator
        )
    }

    func adopt(
        _ tab: Tab,
        for pin: ShortcutPin,
        in windowID: UUID,
        currentSpaceID: UUID?,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> ShortcutTabBindingExecutionReceipt {
        precondition(
            presentationPage.page.windowID == windowID
                && registry.entry(containing: tab) == nil
                && registry.tab(for: pin.id, in: windowID) == nil
        )
        return structuralLookup.withTransaction {
            let execution = bindings.prepareExisting(
                pin,
                to: tab,
                currentSpaceId: currentSpaceID
            )
            membership.attach(tab)
            precondition(registry.register(
                tab,
                for: pin.id,
                in: windowID,
                presentationPage: presentationPage
            ))
            return execution
        }
    }
}
