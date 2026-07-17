import Foundation

/// Active-window tab creation and selection commands for keyboard routing.
@MainActor
final class BrowserKeyboardTabSelectionCommands {
    private let windows: WindowRegistry
    private let windowTabs: BrowserWindowTabContext
    private let opening: BrowserTabOpeningOwner
    private let newTabCommit: FloatingBarCommitService
    private let selection: BrowserTabSelectionOwner

    init(
        windows: WindowRegistry,
        windowTabs: BrowserWindowTabContext,
        opening: BrowserTabOpeningOwner,
        newTabCommit: FloatingBarCommitService,
        selection: BrowserTabSelectionOwner
    ) {
        self.windows = windows
        self.windowTabs = windowTabs
        self.opening = opening
        self.newTabCommit = newTabCommit
        self.selection = selection
    }

    func openNewTabSurfaceInActiveWindow() {
        guard let activeWindow = windows.activeWindow else {
            opening.createNewTab()
            return
        }
        newTabCommit.openNewTabSurface(in: activeWindow)
    }

    func selectRelativeTab(offset: Int) {
        guard let activeWindow = windows.activeWindow else { return }
        let currentTabs = windowTabs.tabsForDisplay(in: activeWindow)
        guard let currentTab = windowTabs.currentTab(for: activeWindow),
              let currentIndex = currentTabs.firstIndex(where: {
                  $0.id == currentTab.id
              }),
              currentTabs.isEmpty == false else {
            return
        }

        let nextIndex = (
            currentIndex + offset + currentTabs.count
        ) % currentTabs.count
        select(currentTabs[nextIndex], in: activeWindow)
    }

    func selectTab(at index: Int) {
        guard let activeWindow = windows.activeWindow else { return }
        let currentTabs = windowTabs.tabsForDisplay(in: activeWindow)
        guard currentTabs.indices.contains(index) else { return }
        select(currentTabs[index], in: activeWindow)
    }

    func selectLastTab() {
        guard let activeWindow = windows.activeWindow,
              let lastTab = windowTabs.tabsForDisplay(in: activeWindow).last else {
            return
        }
        select(lastTab, in: activeWindow)
    }

    func duplicateActiveTab() {
        guard let activeWindow = windows.activeWindow,
              let tab = windowTabs.currentTab(for: activeWindow) else {
            return
        }
        opening.duplicateTab(tab, in: activeWindow)
    }

    private func select(_ tab: Tab, in windowState: BrowserWindowState) {
        _ = selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }
}
