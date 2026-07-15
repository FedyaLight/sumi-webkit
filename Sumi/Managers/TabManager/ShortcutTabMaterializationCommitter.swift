import Foundation

/// Commits one admitted shortcut presentation into canonical membership and
/// residence state inside a single structural-observation transaction.
@MainActor
final class ShortcutTabMaterializationCommitter {
    private let registry: LiveShortcutTabRegistry
    private let bindings: ShortcutTabBindingSynchronizer
    private let freshTabs: ShortcutFreshTabFactory
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        registry: LiveShortcutTabRegistry,
        bindings: ShortcutTabBindingSynchronizer,
        freshTabs: ShortcutFreshTabFactory,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.registry = registry
        self.bindings = bindings
        self.freshTabs = freshTabs
        self.membership = membership
        self.structuralLookup = structuralLookup
    }

    func commit(
        _ pin: ShortcutPin,
        in windowID: UUID,
        currentSpaceID: UUID?,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Tab {
        structuralLookup.withTransaction {
            if let existing = registry.tab(for: pin.id, in: windowID) {
                if let entry = registry.entry(containing: existing),
                   entry.presentationPage != presentationPage {
                    precondition(registry.relocate(
                        existing,
                        from: pin.id,
                        to: pin.id,
                        in: windowID,
                        presentationPage: presentationPage
                    ))
                }
                bindings.applyExisting(
                    pin,
                    to: existing,
                    currentSpaceId: currentSpaceID
                )
                membership.attach(existing)
                return existing
            }

            let tab = freshTabs.makeDetached(
                for: pin,
                currentSpaceID: currentSpaceID
            )
            membership.attach(tab)
            precondition(registry.register(
                tab,
                for: pin.id,
                in: windowID,
                presentationPage: presentationPage
            ))
            return tab
        }
    }
}
