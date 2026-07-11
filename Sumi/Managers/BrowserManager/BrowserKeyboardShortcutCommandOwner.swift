import Foundation
import WebKit

@MainActor
final class BrowserKeyboardShortcutCommandOwner {
    struct TabSelectionCapabilities {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let createNewTab: @MainActor () -> Void
        let openNewTabOrFloatingBar: @MainActor (BrowserWindowState) -> Void
        let tabsForDisplay: @MainActor (BrowserWindowState) -> [Tab]
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    }

    struct SpaceSplitCapabilities {
        let isSplit: @MainActor (UUID) -> Bool
        let setSplitLayoutKind: @MainActor (SplitLayoutKind, UUID) -> Void
        let enterSplitWithTab: @MainActor (Tab, BrowserWindowState) -> Void
        let unsplitActiveGroup: @MainActor (UUID) -> Void
        let createEmptySplit: @MainActor (BrowserWindowState) -> Void
        let spaces: @MainActor () -> [Space]
        let setActiveSpace: @MainActor (Space, BrowserWindowState) -> Void
        let setAllFoldersOpen: @MainActor (Bool, UUID) -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
    }

    struct ReaderCapabilities {
        let activePage: @MainActor () -> ActivePageResolution?
        let toggleReaderMode: @MainActor (WKWebView, Tab) async -> Void
    }

    private let tabSelection: TabSelectionCapabilities
    private let spaceSplit: SpaceSplitCapabilities
    private let reader: ReaderCapabilities

    init(
        tabSelection: TabSelectionCapabilities,
        spaceSplit: SpaceSplitCapabilities,
        reader: ReaderCapabilities
    ) {
        self.tabSelection = tabSelection
        self.spaceSplit = spaceSplit
        self.reader = reader
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            tabSelection: TabSelectionCapabilities(
                activeWindow: { [weak browserManager] in
                    browserManager?.windowRegistry?.activeWindow
                },
                createNewTab: { [weak browserManager] in
                    browserManager?.tabLifecycleService.opening.createNewTab()
                },
                openNewTabOrFloatingBar: { [weak browserManager] windowState in
                    browserManager?.urlBarBundle.floatingBar.commit
                        .openNewTabSurface(in: windowState)
                },
                tabsForDisplay: { [weak browserManager] windowState in
                    browserManager?.shellRuntime.windowTabs.tabsForDisplay(in: windowState) ?? []
                },
                currentTab: { [weak browserManager] windowState in
                    browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
                },
                selectTab: { [weak browserManager] tab, windowState in
                    browserManager?.selectTab(tab, in: windowState)
                }
            ),
            spaceSplit: SpaceSplitCapabilities(
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
                    browserManager?.tabManager.spaceStateOwner.spaces ?? []
                },
                setActiveSpace: { [weak browserManager] space, windowState in
                    browserManager?.windowSpaceTransitions.setActiveSpace(
                        space,
                        in: windowState
                    )
                },
                setAllFoldersOpen: { [weak browserManager] isOpen, spaceId in
                    browserManager?.tabManager.folderMutationOwner.setAllFolders(open: isOpen, in: spaceId)
                },
                persistWindowSession: { [weak browserManager] windowState in
                    browserManager?.windowSessionBundle.persistence.persist(windowState)
                }
            ),
            reader: ReaderCapabilities(
                activePage: { [weak browserManager] in
                    browserManager?.shellRuntime.activePageResolver.resolveActiveWindow()
                },
                toggleReaderMode: { webView, tab in
                    do {
                        try await SumiReaderModeService.toggleReaderMode(on: webView, tab: tab)
                    } catch {
                        RuntimeDiagnostics.debug(category: "ReaderMode") {
                            "Keyboard reader mode toggle failed: \(error.localizedDescription)"
                        }
                    }
                }
            )
        )
    }

    func openNewTabSurfaceInActiveWindow() {
        guard let activeWindow = tabSelection.activeWindow() else {
            tabSelection.createNewTab()
            return
        }

        tabSelection.openNewTabOrFloatingBar(activeWindow)
    }

    func selectNextTabInActiveWindow() {
        selectRelativeTab(offset: 1)
    }

    func selectPreviousTabInActiveWindow() {
        selectRelativeTab(offset: -1)
    }

    func selectTabByIndexInActiveWindow(_ index: Int) {
        guard let activeWindow = tabSelection.activeWindow() else { return }
        let currentTabs = tabSelection.tabsForDisplay(activeWindow)
        guard currentTabs.indices.contains(index) else { return }

        tabSelection.selectTab(currentTabs[index], activeWindow)
    }

    func selectLastTabInActiveWindow() {
        guard let activeWindow = tabSelection.activeWindow(),
              let lastTab = tabSelection.tabsForDisplay(activeWindow).last
        else { return }

        tabSelection.selectTab(lastTab, activeWindow)
    }

    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind) {
        guard let activeWindow = tabSelection.activeWindow() else { return }
        if spaceSplit.isSplit(activeWindow.id) {
            spaceSplit.setSplitLayoutKind(layoutKind, activeWindow.id)
            return
        }
        guard let current = tabSelection.currentTab(activeWindow),
              current.representsSumiNativeSurface == false
        else { return }
        spaceSplit.enterSplitWithTab(current, activeWindow)
        spaceSplit.setSplitLayoutKind(layoutKind, activeWindow.id)
    }

    func unsplitActiveWindow() {
        guard let activeWindow = tabSelection.activeWindow() else { return }
        spaceSplit.unsplitActiveGroup(activeWindow.id)
    }

    func createEmptySplitInActiveWindow() {
        guard let activeWindow = tabSelection.activeWindow() else { return }
        spaceSplit.createEmptySplit(activeWindow)
    }

    func selectNextSpaceInActiveWindow() {
        selectRelativeSpace(offset: 1)
    }

    func selectPreviousSpaceInActiveWindow() {
        selectRelativeSpace(offset: -1)
    }

    func expandAllFoldersInSidebar() {
        guard let windowState = tabSelection.activeWindow(),
              let currentSpaceId = windowState.currentSpaceId
        else { return }
        spaceSplit.setAllFoldersOpen(true, currentSpaceId)
        spaceSplit.persistWindowSession(windowState)
    }

    func toggleReaderModeInActiveWindow() {
        guard let page = reader.activePage(),
              page.tab.representsSumiNativeSurface == false,
              let webView = page.canonicalWebView
        else {
            return
        }

        Task { @MainActor [reader] in
            await reader.toggleReaderMode(webView, page.tab)
        }
    }

    private func selectRelativeTab(offset: Int) {
        guard let activeWindow = tabSelection.activeWindow() else { return }
        let currentTabs = tabSelection.tabsForDisplay(activeWindow)
        guard let currentTab = tabSelection.currentTab(activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id }),
              !currentTabs.isEmpty
        else { return }

        let nextIndex = (currentIndex + offset + currentTabs.count) % currentTabs.count
        tabSelection.selectTab(currentTabs[nextIndex], activeWindow)
    }

    private func selectRelativeSpace(offset: Int) {
        guard let activeWindow = tabSelection.activeWindow(),
              let currentSpaceId = activeWindow.currentSpaceId
        else { return }

        let spaces = spaceSplit.spaces()
        guard let currentSpaceIndex = spaces.firstIndex(where: { $0.id == currentSpaceId }),
              !spaces.isEmpty
        else { return }

        let nextIndex = (currentSpaceIndex + offset + spaces.count) % spaces.count
        spaceSplit.setActiveSpace(spaces[nextIndex], activeWindow)
    }
}
