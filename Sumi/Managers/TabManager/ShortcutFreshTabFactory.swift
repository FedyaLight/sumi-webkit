import Foundation

/// Creates a detached shortcut candidate. Publication into membership and a
/// window residence remains the activation transaction's responsibility.
@MainActor
final class ShortcutFreshTabFactory {
    private let tabFactory: TabFactory
    private let bindings: ShortcutTabBindingSynchronizer

    init(
        tabFactory: TabFactory,
        bindings: ShortcutTabBindingSynchronizer
    ) {
        self.tabFactory = tabFactory
        self.bindings = bindings
    }

    convenience init(tabManager: TabManager) {
        self.init(
            tabFactory: tabManager.tabFactory,
            bindings: tabManager.shortcutTabBindings
        )
    }

    func makeDetached(
        for pin: ShortcutPin,
        currentSpaceID: UUID?
    ) -> Tab {
        let tab = tabFactory.makeTab(
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: nil,
            index: 0
        )
        bindings.initializeFresh(
            tab,
            for: pin,
            currentSpaceId: currentSpaceID
        )
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        return tab
    }
}
