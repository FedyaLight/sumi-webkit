//
//  BrowserManager+KeyboardShortcuts.swift
//  Sumi
//
//

@MainActor
extension BrowserManager {
    // MARK: - Keyboard Shortcut Support Methods

    func openNewTabSurfaceInActiveWindow() {
        keyboardShortcutCommandOwner.openNewTabSurfaceInActiveWindow()
    }

    func selectNextTabInActiveWindow() {
        keyboardShortcutCommandOwner.selectNextTabInActiveWindow()
    }

    func selectPreviousTabInActiveWindow() {
        keyboardShortcutCommandOwner.selectPreviousTabInActiveWindow()
    }

    func selectTabByIndexInActiveWindow(_ index: Int) {
        keyboardShortcutCommandOwner.selectTabByIndexInActiveWindow(index)
    }

    func selectLastTabInActiveWindow() {
        keyboardShortcutCommandOwner.selectLastTabInActiveWindow()
    }

    func setActiveSplitLayout(_ layoutKind: SplitLayoutKind) {
        keyboardShortcutCommandOwner.setActiveSplitLayout(layoutKind)
    }

    func unsplitActiveWindow() {
        keyboardShortcutCommandOwner.unsplitActiveWindow()
    }

    func createEmptySplitInActiveWindow() {
        keyboardShortcutCommandOwner.createEmptySplitInActiveWindow()
    }

    func selectNextSpaceInActiveWindow() {
        keyboardShortcutCommandOwner.selectNextSpaceInActiveWindow()
    }

    func selectPreviousSpaceInActiveWindow() {
        keyboardShortcutCommandOwner.selectPreviousSpaceInActiveWindow()
    }

    // MARK: - Tab Closure Undo Notification

    func presentTabClosureToast(tabCount: Int) {
        presentToast(.init(kind: .tabClosure(count: tabCount)))
    }

    func undoCloseTab() {
        reopenMostRecentClosedItem()
    }

    func expandAllFoldersInSidebar() {
        keyboardShortcutCommandOwner.expandAllFoldersInSidebar()
    }

    func toggleReaderModeInActiveWindow() {
        keyboardShortcutCommandOwner.toggleReaderModeInActiveWindow()
    }
}
