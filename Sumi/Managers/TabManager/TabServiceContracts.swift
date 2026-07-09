import Foundation

@MainActor
final class DefaultTabRuntimeStore: ShellSelectionTabStore {
    private let spacesProvider: () -> [Space]
    private let tabProvider: (UUID) -> Tab?
    private let tabsProvider: (Space) -> [Tab]
    private let shortcutPinProvider: (UUID) -> ShortcutPin?
    private let activeShortcutTabProvider: (UUID) -> Tab?
    private let liveShortcutTabsProvider: (UUID) -> [Tab]
    private let shortcutLiveTabProvider: (UUID, UUID) -> Tab?

    init(
        spaces: @escaping () -> [Space],
        tab: @escaping (UUID) -> Tab?,
        tabs: @escaping (Space) -> [Tab],
        shortcutPin: @escaping (UUID) -> ShortcutPin?,
        activeShortcutTab: @escaping (UUID) -> Tab?,
        liveShortcutTabs: @escaping (UUID) -> [Tab],
        shortcutLiveTab: @escaping (UUID, UUID) -> Tab?
    ) {
        self.spacesProvider = spaces
        self.tabProvider = tab
        self.tabsProvider = tabs
        self.shortcutPinProvider = shortcutPin
        self.activeShortcutTabProvider = activeShortcutTab
        self.liveShortcutTabsProvider = liveShortcutTabs
        self.shortcutLiveTabProvider = shortcutLiveTab
    }

    convenience init(tabManager: TabManager) {
        self.init(
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

    var spaces: [Space] { spacesProvider() }

    func tab(for id: UUID) -> Tab? {
        tabProvider(id)
    }

    func tabs(in space: Space) -> [Tab] {
        tabsProvider(space)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        shortcutPinProvider(id)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        activeShortcutTabProvider(windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        liveShortcutTabsProvider(windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        shortcutLiveTabProvider(pinId, windowId)
    }
}
