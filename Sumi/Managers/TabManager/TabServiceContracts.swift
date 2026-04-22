import Foundation

@MainActor
final class DefaultTabRuntimeStore: ShellSelectionTabStore {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var currentTab: Tab? { tabManager.currentTab }
    var spaces: [Space] { tabManager.spaces }

    func tab(for id: UUID) -> Tab? {
        tabManager.tab(for: id)
    }

    func tabs(in space: Space) -> [Tab] {
        tabManager.tabs(in: space)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        tabManager.shortcutPin(by: id)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        tabManager.activeShortcutTab(for: windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        tabManager.liveShortcutTabs(in: windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        tabManager.shortcutLiveTab(for: pinId, in: windowId)
    }

    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: currentSpaceId)
    }
}
