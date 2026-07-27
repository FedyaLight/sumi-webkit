import Foundation

/// Maps live shortcut navigation changes back to the owning window session.
/// Regular-tab persistence remains owned by `TabStructuralPersistenceService`.
@MainActor
final class ShortcutLiveSessionPersistence {
    private let liveTabs: LiveShortcutTabRegistry
    private let windows: @MainActor () -> WindowRegistry?
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        liveTabs: LiveShortcutTabRegistry,
        windows: @escaping @MainActor () -> WindowRegistry?,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.liveTabs = liveTabs
        self.windows = windows
        self.persistence = persistence
    }

    func schedule(for tab: Tab) {
        guard tab.isShortcutLiveInstance,
              let entry = liveTabs.entry(containing: tab),
              let windowState = windows()?.windows[entry.windowId],
              windowState.isIncognito == false
        else { return }
        persistence.schedule(windowState)
    }
}
