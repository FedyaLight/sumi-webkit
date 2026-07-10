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

    convenience init(
        state: TabStateStore,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        presentation: TabShortcutPresentationOwner
    ) {
        self.init(
            spaces: { state.spaces.spaces },
            tab: { membership.tab(for: $0) },
            tabs: { regularTabs.tabs(in: $0) },
            shortcutPin: { state.shortcutPins.shortcutPin(by: $0) },
            activeShortcutTab: { presentation.activeShortcutTab(for: $0) },
            liveShortcutTabs: { presentation.liveShortcutTabs(in: $0) },
            shortcutLiveTab: { presentation.shortcutLiveTab(for: $0, in: $1) }
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
