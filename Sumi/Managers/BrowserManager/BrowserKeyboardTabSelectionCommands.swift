import Foundation

/// Active-window tab creation and selection commands for keyboard routing.
@MainActor
final class BrowserKeyboardTabSelectionCommands {
    private let windowTabs: BrowserWindowTabContext
    private let opening: BrowserTabOpeningOwner
    private let newTabCommit: FloatingBarCommitService
    private let selection: BrowserTabSelectionOwner

    init(
        windowTabs: BrowserWindowTabContext,
        opening: BrowserTabOpeningOwner,
        newTabCommit: FloatingBarCommitService,
        selection: BrowserTabSelectionOwner
    ) {
        self.windowTabs = windowTabs
        self.opening = opening
        self.newTabCommit = newTabCommit
        self.selection = selection
    }

    func openNewTabSurface(in windowState: BrowserWindowState) {
        newTabCommit.openNewTabSurface(in: windowState)
    }

    func selectRelativeTab(
        offset: Int,
        in windowState: BrowserWindowState
    ) {
        let currentTabs = windowTabs.tabsForDisplay(in: windowState)
        guard let currentTab = windowTabs.currentTab(for: windowState),
              let currentIndex = currentTabs.firstIndex(where: {
                  $0.id == currentTab.id
              }),
              currentTabs.isEmpty == false else {
            return
        }

        let nextIndex = (
            currentIndex + offset + currentTabs.count
        ) % currentTabs.count
        select(currentTabs[nextIndex], in: windowState)
    }

    func selectTab(at index: Int, in windowState: BrowserWindowState) {
        let currentTabs = windowTabs.tabsForDisplay(in: windowState)
        guard currentTabs.indices.contains(index) else { return }
        select(currentTabs[index], in: windowState)
    }

    func selectLastTab(in windowState: BrowserWindowState) {
        guard let lastTab = windowTabs.tabsForDisplay(in: windowState).last else {
            return
        }
        select(lastTab, in: windowState)
    }

    func duplicateTab(in windowState: BrowserWindowState) {
        guard let tab = windowTabs.currentTab(for: windowState) else {
            return
        }
        opening.duplicateTab(tab, in: windowState)
    }

    private func select(_ tab: Tab, in windowState: BrowserWindowState) {
        _ = selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }
}
