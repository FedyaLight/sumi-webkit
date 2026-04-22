import Foundation
import WebKit

@MainActor
protocol TabRepository: AnyObject {
    func scheduleStructuralPersistence()
    func flushStructuralPersistenceAwaitingResult() async -> Bool
    func persistFullReconcileAwaitingResult(reason: String) async -> Bool
}

@MainActor
protocol TabRuntimeStateStore: AnyObject {
    var currentSpace: Space? { get }
    var currentTab: Tab? { get }
    var spaces: [Space] { get }

    func allTabs() -> [Tab]
    func tab(for id: UUID) -> Tab?
    func tabs(in space: Space) -> [Tab]
    func shortcutPin(by id: UUID) -> ShortcutPin?
    func activeShortcutTab(for windowId: UUID) -> Tab?
    func liveShortcutTabs(in windowId: UUID) -> [Tab]
    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab?
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab
}

@MainActor
protocol TabMutating: AnyObject {
    @discardableResult
    func createNewTab(
        url: String,
        in space: Space?,
        activate: Bool,
        webViewConfigurationOverride: WKWebViewConfiguration?
    ) -> Tab

    func setActiveSpace(_ space: Space, preferredTab: Tab?)
    func removeShortcutPin(_ pin: ShortcutPin)
    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab
}

@MainActor
final class TabRepositoryService: TabRepository {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func scheduleStructuralPersistence() {
        tabManager.scheduleStructuralPersistence()
    }

    func flushStructuralPersistenceAwaitingResult() async -> Bool {
        await tabManager.flushStructuralPersistenceAwaitingResult()
    }

    func persistFullReconcileAwaitingResult(reason: String) async -> Bool {
        await tabManager.persistFullReconcileAwaitingResult(reason: reason)
    }
}

@MainActor
final class DefaultTabRuntimeStore: TabRuntimeStateStore, ShellSelectionTabStore {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var currentSpace: Space? { tabManager.currentSpace }
    var currentTab: Tab? { tabManager.currentTab }
    var spaces: [Space] { tabManager.spaces }

    func allTabs() -> [Tab] {
        tabManager.allTabs()
    }

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

@MainActor
final class TabMutationService: TabMutating {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil
    ) -> Tab {
        tabManager.createNewTab(
            url: url,
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride
        )
    }

    func setActiveSpace(_ space: Space, preferredTab: Tab? = nil) {
        tabManager.setActiveSpace(space, preferredTab: preferredTab)
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        tabManager.removeShortcutPin(pin)
    }

    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: currentSpaceId)
    }
}
