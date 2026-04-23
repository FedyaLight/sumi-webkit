//
//  BrowserManager+History.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
extension BrowserManager {
    enum HistoryOpenMode {
        case currentTab
        case newTab
        case newWindow
    }

    var canOfferStartupLastSessionRestoreShortcut: Bool {
        !didConsumeStartupLastSessionRestoreOffer
            && startupLastSessionWindowSnapshots.count > 1
            && currentRegularWindowSnapshots(excludingWindowID: nil).count <= 1
    }

    var canRestoreAnyLastSession: Bool {
        canOfferStartupLastSessionRestoreShortcut || lastSessionWindowsStore.canRestoreLastSession
    }

    var canGoBackInActiveWindow: Bool {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = currentTab(for: activeWindow),
              let webView = getWebView(for: currentTab.id, in: activeWindow.id)
        else {
            return false
        }
        return webView.canGoBack
    }

    var canGoForwardInActiveWindow: Bool {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = currentTab(for: activeWindow),
              let webView = getWebView(for: currentTab.id, in: activeWindow.id)
        else {
            return false
        }
        return webView.canGoForward
    }

    func goBackInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = currentTab(for: activeWindow),
              let webView = getWebView(for: currentTab.id, in: activeWindow.id),
              webView.canGoBack
        else {
            return
        }
        webView.goBack()
    }

    func goForwardInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = currentTab(for: activeWindow),
              let webView = getWebView(for: currentTab.id, in: activeWindow.id),
              webView.canGoForward
        else {
            return
        }
        webView.goForward()
    }

    func openHistoryTab(
        selecting range: DataModel.HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? windowRegistry?.activeWindow {
            openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
            return
        }

        let existingWindowIDs = Set(windowRegistry?.windows.keys.map { $0 } ?? [])
        createNewWindow()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await self.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                  )
            else {
                return
            }
            self.openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
        }
    }

    private func openHistoryTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting range: DataModel.HistoryRange
    ) {
        let historyURL = SumiSurface.historySurfaceURL(rangeQuery: range.paneQueryValue)
        let newTab = openNewTab(
            url: historyURL.absoluteString,
            context: .foreground(
                windowState: targetWindow,
                preferredSpaceId: targetWindow.currentSpaceId,
                loadPolicy: .deferred
            )
        )
        newTab.name = "History"
        newTab.favicon = Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
        newTab.faviconIsTemplateGlobePlaceholder = false
        targetWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        if let activeWindow = windowRegistry?.activeWindow {
            openHistoryURL(url, in: activeWindow, preferredOpenMode: .currentTab)
        } else {
            openHistoryURLsInNewWindow([url])
        }
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        switch preferredOpenMode {
        case .currentTab:
            if let currentTab = currentTab(for: windowState),
               !currentTab.representsSumiEmptySurface
            {
                currentTab.loadURL(url)
            } else {
                let newTab = openNewTab(
                    url: url.absoluteString,
                    context: .foreground(windowState: windowState)
                )
                newTab.name = url.host ?? url.absoluteString
            }
        case .newTab:
            let newTab = openNewTab(
                url: url.absoluteString,
                context: .foreground(windowState: windowState)
            )
            newTab.name = url.host ?? url.absoluteString
        case .newWindow:
            openHistoryURLsInNewWindow([url])
        }
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        for (index, url) in uniqueURLs.enumerated() {
            let context: TabOpenContext
            if index == 0 {
                context = .foreground(windowState: windowState)
            } else {
                context = .background(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            }
            let tab = openNewTab(url: url.absoluteString, context: context)
            tab.name = url.host ?? url.absoluteString
        }
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        let existingWindowIDs = Set(windowRegistry?.windows.keys.map { $0 } ?? [])
        createNewWindow()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await self.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                  )
            else {
                return
            }
            self.openHistoryURLsInNewTabs(uniqueURLs, in: targetWindow)
        }
    }

    func reopenLastClosedItem() {
        if canOfferStartupLastSessionRestoreShortcut {
            reopenAllWindowsFromLastSession()
            return
        }

        guard let item = recentlyClosedManager.mostRecentItem else { return }
        reopenRecentlyClosedItem(item)
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        switch item {
        case .tab(let tabState):
            reopenClosedTab(tabState)
        case .window(let windowState):
            Task {
                await reopenWindow(from: windowState.session)
            }
        }
        recentlyClosedManager.remove(item)
        didConsumeStartupLastSessionRestoreOffer = true
    }

    func reopenAllWindowsFromLastSession() {
        let sourceSnapshots = canOfferStartupLastSessionRestoreShortcut
            ? startupLastSessionWindowSnapshots
            : lastSessionWindowsStore.snapshots
        let existingSessions = Set(currentRegularWindowSnapshots(excludingWindowID: nil).map(\.session))
        let snapshotsToRestore = sourceSnapshots.filter { !existingSessions.contains($0.session) }
        guard !snapshotsToRestore.isEmpty else { return }

        didConsumeStartupLastSessionRestoreOffer = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            for snapshot in snapshotsToRestore {
                await self.reopenWindow(from: snapshot.session)
            }
            self.refreshLastSessionWindowsStore(excludingWindowID: nil)
        }
    }

    func clearAllHistoryFromMenu() {
        let alert = NSAlert()
        alert.messageText = "Clear All History"
        alert.informativeText = "This will permanently remove all browsing history for the current profile."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await historyManager.clearAll()
            }
        }
    }

    func handleWindowWillClose(_ windowId: UUID) {
        guard let windowState = windowRegistry?.windows[windowId],
              !windowState.isIncognito
        else {
            refreshLastSessionWindowsStore(excludingWindowID: windowId)
            return
        }

        let snapshot = windowSessionService.makeWindowSessionSnapshot(
            for: windowState,
            delegate: self
        )
        if snapshot.currentTabId != nil || snapshot.splitSession != nil || !snapshot.isShowingEmptyState {
            recentlyClosedManager.captureClosedWindow(
                title: windowDisplayTitle(for: windowState),
                session: snapshot
            )
        }

        refreshLastSessionWindowsStore(excludingWindowID: windowId)
    }

    func refreshLastSessionWindowsStore(excludingWindowID: UUID?) {
        var snapshots = currentRegularWindowSnapshots(excludingWindowID: excludingWindowID)
        if snapshots.isEmpty, excludingWindowID != nil {
            snapshots = currentRegularWindowSnapshots(excludingWindowID: nil)
        }
        if snapshots.count > 1 {
            didConsumeStartupLastSessionRestoreOffer = true
        }
        lastSessionWindowsStore.updateSnapshots(snapshots)
    }

    private func reopenClosedTab(_ tabState: RecentlyClosedTabState) {
        let targetWindow = windowRegistry?.activeWindow
        let targetSpace = tabState.sourceSpaceId.flatMap { space(for: $0) }
            ?? targetWindow?.currentSpaceId.flatMap { space(for: $0) }
            ?? tabManager.currentSpace

        let restoredTab = tabManager.createNewTab(
            url: (tabState.currentURL ?? tabState.url).absoluteString,
            in: targetSpace,
            activate: false
        )
        restoredTab.name = tabState.title
        restoredTab.restoredCanGoBack = tabState.canGoBack
        restoredTab.restoredCanGoForward = tabState.canGoForward

        if let targetWindow {
            selectTab(restoredTab, in: targetWindow)
        } else {
            tabManager.setActiveTab(restoredTab)
        }
    }

    private func reopenWindow(from snapshot: WindowSessionSnapshot) async {
        let existingWindowIDs = Set(windowRegistry?.windows.keys.map { $0 } ?? [])
        createNewWindow()
        guard let targetWindow = await windowRegistry?.awaitNextRegisteredWindow(
            excluding: existingWindowIDs
        ) else {
            return
        }

        windowSessionService.applyWindowSessionSnapshot(
            snapshot,
            to: targetWindow,
            delegate: self
        )
        targetWindow.window?.makeKeyAndOrderFront(nil as Any?)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func currentRegularWindowSnapshots(
        excludingWindowID: UUID?
    ) -> [LastSessionWindowSnapshot] {
        let regularWindows = (windowRegistry?.allWindows ?? [])
            .filter { $0.isIncognito == false }
            .filter { $0.id != excludingWindowID }

        return regularWindows.map { windowState in
            LastSessionWindowSnapshot(
                id: windowState.id,
                session: windowSessionService.makeWindowSessionSnapshot(
                    for: windowState,
                    delegate: self
                )
            )
        }
    }

    private func windowDisplayTitle(for windowState: BrowserWindowState) -> String {
        if let currentTab = currentTab(for: windowState) {
            return currentTab.name
        }
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace.name
        }
        return "Window"
    }
}
