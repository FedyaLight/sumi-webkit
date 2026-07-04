import Foundation

@MainActor
final class DefaultTabRuntimeStore: ShellSelectionTabStore {
    struct Dependencies {
        let spaces: () -> [Space]
        let tab: (UUID) -> Tab?
        let tabs: (Space) -> [Tab]
        let shortcutPin: (UUID) -> ShortcutPin?
        let activeShortcutTab: (UUID) -> Tab?
        let liveShortcutTabs: (UUID) -> [Tab]
        let shortcutLiveTab: (UUID, UUID) -> Tab?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var spaces: [Space] { dependencies.spaces() }

    func tab(for id: UUID) -> Tab? {
        dependencies.tab(id)
    }

    func tabs(in space: Space) -> [Tab] {
        dependencies.tabs(space)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        dependencies.shortcutPin(id)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        dependencies.activeShortcutTab(windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        dependencies.liveShortcutTabs(windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        dependencies.shortcutLiveTab(pinId, windowId)
    }
}

extension DefaultTabRuntimeStore.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            tab: { [weak tabManager] id in
                tabManager?.tabCollectionMembershipOwner.tab(for: id)
            },
            tabs: { [weak tabManager] space in
                tabManager?.regularTabCollectionOwner.tabs(in: space) ?? []
            },
            shortcutPin: { [weak tabManager] id in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: id)
            },
            activeShortcutTab: { [weak tabManager] windowId in
                tabManager?.shortcutPresentationOwner.activeShortcutTab(for: windowId)
            },
            liveShortcutTabs: { [weak tabManager] windowId in
                tabManager?.shortcutPresentationOwner.liveShortcutTabs(in: windowId) ?? []
            },
            shortcutLiveTab: { [weak tabManager] pinId, windowId in
                tabManager?.shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowId)
            }
        )
    }
}
