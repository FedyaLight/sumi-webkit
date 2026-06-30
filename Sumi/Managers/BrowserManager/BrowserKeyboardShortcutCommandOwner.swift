import Foundation
import WebKit

@MainActor
final class BrowserKeyboardShortcutCommandOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let createNewTab: @MainActor () -> Void
        let openNewTabOrFloatingBar: @MainActor (BrowserWindowState) -> Void
        let tabsForDisplay: @MainActor (BrowserWindowState) -> [Tab]
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
        let isSplit: @MainActor (UUID) -> Bool
        let setSplitLayoutKind: @MainActor (SplitLayoutKind, UUID) -> Void
        let enterSplitWithTab: @MainActor (Tab, BrowserWindowState) -> Void
        let unsplitActiveGroup: @MainActor (UUID) -> Void
        let createEmptySplit: @MainActor (BrowserWindowState) -> Void
        let spaces: @MainActor () -> [Space]
        let setActiveSpace: @MainActor (Space, BrowserWindowState) -> Void
        let setAllFoldersOpen: @MainActor (Bool, UUID) -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let activePageTab: @MainActor () -> Tab?
        let activePageWebView: @MainActor () -> WKWebView?
        let webView: @MainActor (UUID, UUID) -> WKWebView?
        let toggleReaderMode: @MainActor (WKWebView, Tab) async -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func openNewTabSurfaceInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow() else {
            dependencies.createNewTab()
            return
        }

        dependencies.openNewTabOrFloatingBar(activeWindow)
    }

    func selectNextTabInActiveWindow() {
        selectRelativeTab(offset: 1)
    }

    func selectPreviousTabInActiveWindow() {
        selectRelativeTab(offset: -1)
    }

    func selectTabByIndexInActiveWindow(_ index: Int) {
        guard let activeWindow = dependencies.activeWindow() else { return }
        let currentTabs = dependencies.tabsForDisplay(activeWindow)
        guard currentTabs.indices.contains(index) else { return }

        dependencies.selectTab(currentTabs[index], activeWindow)
    }

    func selectLastTabInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow(),
              let lastTab = dependencies.tabsForDisplay(activeWindow).last
        else { return }

        dependencies.selectTab(lastTab, activeWindow)
    }

    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind) {
        guard let activeWindow = dependencies.activeWindow() else { return }
        if dependencies.isSplit(activeWindow.id) {
            dependencies.setSplitLayoutKind(layoutKind, activeWindow.id)
            return
        }
        guard let current = dependencies.currentTab(activeWindow),
              current.representsSumiNativeSurface == false
        else { return }
        dependencies.enterSplitWithTab(current, activeWindow)
        dependencies.setSplitLayoutKind(layoutKind, activeWindow.id)
    }

    func unsplitActiveWindow() {
        guard let activeWindow = dependencies.activeWindow() else { return }
        dependencies.unsplitActiveGroup(activeWindow.id)
    }

    func createEmptySplitInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow() else { return }
        dependencies.createEmptySplit(activeWindow)
    }

    func selectNextSpaceInActiveWindow() {
        selectRelativeSpace(offset: 1)
    }

    func selectPreviousSpaceInActiveWindow() {
        selectRelativeSpace(offset: -1)
    }

    func expandAllFoldersInSidebar() {
        guard let windowState = dependencies.activeWindow(),
              let currentSpaceId = windowState.currentSpaceId
        else { return }
        dependencies.setAllFoldersOpen(true, currentSpaceId)
        dependencies.persistWindowSession(windowState)
    }

    func toggleReaderModeInActiveWindow() {
        guard let tab = dependencies.activePageTab(),
              tab.representsSumiNativeSurface == false,
              let windowState = dependencies.activeWindow(),
              let webView = dependencies.activePageWebView()
                ?? dependencies.webView(tab.id, windowState.id)
        else {
            return
        }

        Task { @MainActor [dependencies] in
            await dependencies.toggleReaderMode(webView, tab)
        }
    }

    private func selectRelativeTab(offset: Int) {
        guard let activeWindow = dependencies.activeWindow() else { return }
        let currentTabs = dependencies.tabsForDisplay(activeWindow)
        guard let currentTab = dependencies.currentTab(activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id }),
              !currentTabs.isEmpty
        else { return }

        let nextIndex = (currentIndex + offset + currentTabs.count) % currentTabs.count
        dependencies.selectTab(currentTabs[nextIndex], activeWindow)
    }

    private func selectRelativeSpace(offset: Int) {
        guard let activeWindow = dependencies.activeWindow(),
              let currentSpaceId = activeWindow.currentSpaceId
        else { return }

        let spaces = dependencies.spaces()
        guard let currentSpaceIndex = spaces.firstIndex(where: { $0.id == currentSpaceId }),
              !spaces.isEmpty
        else { return }

        let nextIndex = (currentSpaceIndex + offset + spaces.count) % spaces.count
        dependencies.setActiveSpace(spaces[nextIndex], activeWindow)
    }
}

extension BrowserKeyboardShortcutCommandOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            createNewTab: { [weak browserManager] in
                browserManager?.createNewTab()
            },
            openNewTabOrFloatingBar: { [weak browserManager] windowState in
                browserManager?.openNewTabOrFloatingBar(in: windowState)
            },
            tabsForDisplay: { [weak browserManager] windowState in
                browserManager?.tabsForDisplay(in: windowState) ?? []
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            isSplit: { [weak browserManager] windowId in
                browserManager?.splitManager.isSplit(for: windowId) ?? false
            },
            setSplitLayoutKind: { [weak browserManager] layoutKind, windowId in
                browserManager?.splitManager.setLayoutKind(layoutKind, for: windowId)
            },
            enterSplitWithTab: { [weak browserManager] tab, windowState in
                browserManager?.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState)
            },
            unsplitActiveGroup: { [weak browserManager] windowId in
                browserManager?.splitManager.unsplitActiveGroup(for: windowId)
            },
            createEmptySplit: { [weak browserManager] windowState in
                browserManager?.splitManager.createEmptySplit(side: .right, in: windowState)
            },
            spaces: { [weak browserManager] in
                browserManager?.tabManager.spaces ?? []
            },
            setActiveSpace: { [weak browserManager] space, windowState in
                browserManager?.setActiveSpace(space, in: windowState)
            },
            setAllFoldersOpen: { [weak browserManager] isOpen, spaceId in
                browserManager?.tabManager.setAllFolders(open: isOpen, in: spaceId)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            activePageTab: { [weak browserManager] in
                browserManager?.activePageTabForActiveWindow()
            },
            activePageWebView: { [weak browserManager] in
                browserManager?.activePageWebViewForActiveWindow()
            },
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.getWebView(for: tabId, in: windowId)
            },
            toggleReaderMode: { webView, tab in
                try? await SumiReaderModeService.toggleReaderMode(on: webView, tab: tab)
            }
        )
    }
}
