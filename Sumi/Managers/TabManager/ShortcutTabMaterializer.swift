import Foundation

/// Creates or reuses the one live shortcut instance for a `(window, pin)` slot.
@MainActor
final class ShortcutTabMaterializer {
    private let registry: LiveShortcutTabRegistry
    private let bindings: ShortcutTabBindingSynchronizer
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let tabFactory: TabFactory

    init(
        registry: LiveShortcutTabRegistry,
        bindings: ShortcutTabBindingSynchronizer,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        tabFactory: TabFactory
    ) {
        self.registry = registry
        self.bindings = bindings
        self.membership = membership
        self.structuralLookup = structuralLookup
        self.tabFactory = tabFactory
    }

    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            bindings: tabManager.shortcutTabBindings,
            membership: tabManager.tabCollectionMembershipOwner,
            structuralLookup: tabManager.structuralLookupCoordinator,
            tabFactory: tabManager.tabFactory
        )
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowId: UUID,
        currentSpaceId: UUID?
    ) -> Tab {
        structuralLookup.withTransaction {
            if let existing = registry.tab(for: pin.id, in: windowId) {
                let changed = bindings.applyExisting(
                    pin,
                    to: existing,
                    currentSpaceId: currentSpaceId
                )
                membership.attach(existing)
                if changed { structuralLookup.requestPublish() }
                return existing
            }

            let tab = tabFactory.makeTab(
                url: pin.launchURL,
                name: pin.title,
                favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                spaceId: nil,
                index: 0
            )
            _ = bindings.initializeFresh(
                tab,
                for: pin,
                currentSpaceId: currentSpaceId
            )
            _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
            membership.attach(tab)
            registry.register(tab, for: pin.id, in: windowId)
            return tab
        }
    }

    func adopt(
        _ tab: Tab,
        for pin: ShortcutPin,
        in windowId: UUID,
        currentSpaceId: UUID?
    ) {
        structuralLookup.withTransaction {
            precondition(
                registry.entry(containing: tab) == nil,
                "Cannot adopt a tab already leased by the live shortcut registry"
            )
            precondition(
                registry.tab(for: pin.id, in: windowId) == nil,
                "Cannot replace a live shortcut registry slot while adopting a tab"
            )
            _ = bindings.applyExisting(
                pin,
                to: tab,
                currentSpaceId: currentSpaceId
            )
            membership.attach(tab)
            registry.register(tab, for: pin.id, in: windowId)
        }
    }
}
