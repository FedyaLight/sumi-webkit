import Foundation

@MainActor
final class DefaultTabRuntimeStore: ShellSelectionTabStore {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var spaces: [Space] { tabManager.spaces }

    func tab(for id: UUID) -> Tab? {
        tabManager.tab(for: id)
    }

    func tabs(in space: Space) -> [Tab] {
        tabManager.tabs(in: space)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: id)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        tabManager.shortcutPresentationOwner.activeShortcutTab(for: windowId)
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        tabManager.shortcutPresentationOwner.liveShortcutTabs(in: windowId)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pinId, in: windowId)
    }
}
