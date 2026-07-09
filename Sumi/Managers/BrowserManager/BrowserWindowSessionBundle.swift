//
//  BrowserWindowSessionBundle.swift
//  Sumi
//
//  Phase 5A capability bag: window session activation, history, restore, shell commands.
//

import Foundation

/// Groups window-session owners and the Phase 4C window-session command façade.
/// `WindowSessionService` stays on BrowserManager so tests can replace the
/// session key / service before the bag's lazy owners are first touched.
@MainActor
final class BrowserWindowSessionBundle {
    let commands: BrowserWindowSessionCommands
    let activationOwner: BrowserWindowSessionActivationOwner
    let historySessionOwner: BrowserWindowHistorySessionOwner
    let recentlyClosedRestoreOwner: BrowserRecentlyClosedRestoreOwner

    init(
        browserManager: BrowserManager,
        startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    ) {
        self.commands = BrowserWindowSessionCommands(browserManager: browserManager)
        self.recentlyClosedRestoreOwner = BrowserRecentlyClosedRestoreOwner(
            dependencies: .live(browserManager: browserManager)
        )
        self.historySessionOwner = BrowserWindowHistorySessionOwner(
            dependencies: BrowserWindowHistorySessionOwner.Dependencies(
                windowState: { [weak browserManager] windowId in
                    browserManager?.windowRegistry?.windows[windowId]
                },
                allWindows: { [weak browserManager] in
                    browserManager?.windowRegistry?.allWindows ?? []
                },
                makeWindowSessionSnapshot: { [weak browserManager] windowState in
                    guard let browserManager else { return nil }
                    return browserManager.windowSessionService.makeWindowSessionSnapshot(
                        for: windowState,
                        runtime: WindowSessionRuntimeFactory.make(for: browserManager)
                    )
                },
                windowDisplayTitle: { [weak browserManager] windowState in
                    guard let browserManager else { return "" }
                    if let currentTab = browserManager.windowTabContextOwner.currentTab(for: windowState) {
                        return currentTab.name
                    }
                    if let currentSpace = browserManager.windowSpaceStateOwner.space(
                        for: windowState.currentSpaceId
                    ) {
                        return currentSpace.name
                    }
                    return "Window"
                },
                recentlyClosedManager: {
                    [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                    browserManager?.recentlyClosedManager ?? recentlyClosedManager
                },
                lastSessionWindowsStore: {
                    [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                    browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
                },
                startupRestore: startupSessionRestoreOwner
            )
        )
        self.activationOwner = BrowserWindowSessionActivationOwner(
            dependencies: .live(browserManager: browserManager)
        )
    }
}
