//
//  BrowserManager+KeyboardShortcuts.swift
//  Sumi
//
//  Created by OpenAI Codex on 06/04/2026.
//

import Foundation

@MainActor
extension BrowserManager {
    // MARK: - Keyboard Shortcut Support Methods

    func openNewTabSurfaceInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else {
            createNewTab()
            return
        }

        if activeWindow.isCommandPaletteVisible,
           activeWindow.commandPalettePresentationReason == .emptySpace
        {
            openCommandPalette(in: activeWindow, reason: .emptySpace)
            return
        }

        if currentTab(for: activeWindow)?.representsSumiEmptySurface == true {
            openCommandPalette(in: activeWindow, reason: .emptySpace)
            return
        }

        openCommandPalette(in: activeWindow, reason: .emptySpace)
    }

    func selectNextTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let nextIndex = (currentIndex + 1) % currentTabs.count
        if let nextTab = currentTabs[safe: nextIndex] {
            selectTab(nextTab, in: activeWindow)
        }
    }

    func selectPreviousTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard let currentTab = currentTab(for: activeWindow),
              let currentIndex = currentTabs.firstIndex(where: { $0.id == currentTab.id })
        else { return }

        let previousIndex = currentIndex > 0 ? currentIndex - 1 : currentTabs.count - 1
        if let previousTab = currentTabs[safe: previousIndex] {
            selectTab(previousTab, in: activeWindow)
        }
    }

    func selectTabByIndexInActiveWindow(_ index: Int) {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        let currentTabs = tabsForDisplay(in: activeWindow)
        guard currentTabs.indices.contains(index) else { return }

        selectTab(currentTabs[index], in: activeWindow)
    }

    func selectLastTabInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let lastTab = tabsForDisplay(in: activeWindow).last
        else { return }

        selectTab(lastTab, in: activeWindow)
    }

    func selectNextSpaceInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentSpaceId = activeWindow.currentSpaceId,
              let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })
        else { return }

        let nextIndex = (currentSpaceIndex + 1) % tabManager.spaces.count
        if let nextSpace = tabManager.spaces[safe: nextIndex] {
            setActiveSpace(nextSpace, in: activeWindow)
        }
    }

    func selectPreviousSpaceInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentSpaceId = activeWindow.currentSpaceId,
              let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })
        else { return }

        let previousIndex = currentSpaceIndex > 0 ? currentSpaceIndex - 1 : tabManager.spaces.count - 1
        if let previousSpace = tabManager.spaces[safe: previousIndex] {
            setActiveSpace(previousSpace, in: activeWindow)
        }
    }

    // MARK: - Tab Closure Undo Notification

    func showTabClosureToast(tabCount: Int) {
        tabClosureToastCount = tabCount
        showTabClosureToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.hideTabClosureToast()
        }
    }

    func hideTabClosureToast() {
        showTabClosureToast = false
        tabClosureToastCount = 0
    }

    func undoCloseTab() {
        tabManager.undoCloseTab()
    }

    func expandAllFoldersInSidebar() {
        guard let windowState = windowRegistry?.activeWindow,
              let currentSpaceId = windowState.currentSpaceId
        else { return }
        tabManager.setAllFolders(open: true, in: currentSpaceId)
        persistWindowSession(for: windowState)
    }
}
