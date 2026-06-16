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
            && !startupLastSessionWindowSnapshots.isEmpty
    }

    var canRestoreAnyLastSession: Bool {
        canOfferStartupLastSessionRestoreShortcut || lastSessionWindowsStore.canRestoreLastSession
    }

    var canGoBackInActiveWindow: Bool {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = activePageTab(for: activeWindow),
              let webView = activePageWebView(for: activeWindow)
                ?? webViewCoordinator?.getWebView(for: currentTab.id, in: activeWindow.id)
        else {
            return false
        }
        return webView.canGoBack
    }

    var canGoForwardInActiveWindow: Bool {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = activePageTab(for: activeWindow),
              let webView = activePageWebView(for: activeWindow)
                ?? webViewCoordinator?.getWebView(for: currentTab.id, in: activeWindow.id)
        else {
            return false
        }
        return webView.canGoForward
    }

    func goBackInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = activePageTab(for: activeWindow),
              let webView = activePageWebView(for: activeWindow)
                ?? webViewCoordinator?.getWebView(for: currentTab.id, in: activeWindow.id),
              webView.canGoBack
        else {
            return
        }
        webView.goBack()
    }

    func goForwardInActiveWindow() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = activePageTab(for: activeWindow),
              let webView = activePageWebView(for: activeWindow)
                ?? webViewCoordinator?.getWebView(for: currentTab.id, in: activeWindow.id),
              webView.canGoForward
        else {
            return
        }
        webView.goForward()
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
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
        selecting range: HistoryRange
    ) {
        openNativeBrowserSurface(
            .history,
            url: SumiSurface.historySurfaceURL(rangeQuery: range.paneQueryValue),
            in: targetWindow,
            preferredSpaceId: targetWindow.currentSpaceId
        )
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
            if let currentTab = activePageTab(for: windowState),
               !currentTab.representsSumiEmptySurface
            {
                if currentTab.representsSumiHistorySurface {
                    replaceNativeHistoryTab(currentTab, with: url, in: windowState)
                } else {
                    currentTab.loadURL(url)
                }
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

    private func replaceNativeHistoryTab(
        _ tab: Tab,
        with url: URL,
        in windowState: BrowserWindowState
    ) {
        tab.name = url.host ?? url.absoluteString
        tab.favicon = Image(systemName: "globe")
        tab.faviconIsTemplateGlobePlaceholder = true
        tab.loadURL(url)
        windowState.invalidateNativeSurfaceRouting()
        tabManager.scheduleRuntimeStatePersistence(for: tab)
        schedulePrepareVisibleWebViews(for: windowState)
        refreshCompositor(for: windowState)

        Task { @MainActor [weak tab] in
            guard let tab else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
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

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        openURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
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
            self.openURLsInNewTabs(uniqueURLs, in: targetWindow)
        }
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        openURLsInNewWindow(urls)
    }

    func reopenMostRecentClosedItem() {
        guard let item = recentlyClosedManager.mostRecentItem else { return }
        reopenRecentlyClosedItem(item)
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        switch item {
        case .tab(let tabState):
            reopenClosedTab(tabState)
        case .shortcutLiveInstance(let shortcutState):
            reopenClosedShortcutLiveInstance(shortcutState)
        case .shortcutLauncher(let launcherState):
            restoreShortcutLauncher(from: launcherState.pin)
        case .window(let windowState):
            Task {
                await reopenWindow(from: windowState.session)
            }
        }
        recentlyClosedManager.remove(item)
        didConsumeStartupLastSessionRestoreOffer = true
    }

    func reopenAllWindowsFromLastSession() {
        let useStartupArchive = canOfferStartupLastSessionRestoreShortcut
        let sourceSnapshots = useStartupArchive
            ? startupLastSessionWindowSnapshots
            : lastSessionWindowsStore.snapshots
        let sourceTabSnapshot = useStartupArchive
            ? (startupLastSessionTabSnapshot ?? lastSessionWindowsStore.tabSnapshot)
            : lastSessionWindowsStore.tabSnapshot
        let existingSessions = Set(currentRegularWindowSnapshots(excludingWindowID: nil).map(\.session))
        let snapshotsToRestore = sourceSnapshots.filter { !existingSessions.contains($0.session) }
        guard !snapshotsToRestore.isEmpty else { return }

        didConsumeStartupLastSessionRestoreOffer = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let sourceTabSnapshot {
                self.tabManager.mergeSnapshotForLastSessionRestore(sourceTabSnapshot)
            }
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
        requestCollapsedSidebarOverlayDismissal()
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
        if canOfferStartupLastSessionRestoreShortcut,
           let startupLastSessionTabSnapshot
        {
            lastSessionWindowsStore.updateSnapshots(
                startupLastSessionWindowSnapshots,
                tabSnapshot: startupLastSessionTabSnapshot
            )
            return
        }

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

    private func reopenClosedShortcutLiveInstance(_ shortcutState: RecentlyClosedShortcutLiveState) {
        guard let targetWindow = targetWindowForClosedShortcut(shortcutState) else {
            if tabManager.shortcutPin(by: shortcutState.pin.id) == nil {
                restoreShortcutLauncher(from: shortcutState.pin)
            }
            return
        }

        guard let pin = tabManager.shortcutPin(by: shortcutState.pin.id) else {
            restoreShortcutLauncher(from: shortcutState.pin, fallbackWindow: targetWindow)
            return
        }

        let restoredTab = tabManager.activateShortcutPin(
            pin,
            in: targetWindow.id,
            currentSpaceId: targetWindow.currentSpaceId
        )
        applyShortcutLiveState(shortcutState, to: restoredTab)
        selectTab(restoredTab, in: targetWindow)
    }

    private func targetWindowForClosedShortcut(_ shortcutState: RecentlyClosedShortcutLiveState) -> BrowserWindowState? {
        if let sourceWindowId = shortcutState.sourceWindowId,
           let sourceWindow = windowRegistry?.windows[sourceWindowId] {
            return sourceWindow
        }
        return windowRegistry?.activeWindow
    }

    private func applyShortcutLiveState(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        to tab: Tab
    ) {
        tab.name = shortcutState.title
        tab.url = shortcutState.url
        tab.restoredCanGoBack = shortcutState.canGoBack
        tab.restoredCanGoForward = shortcutState.canGoForward
        _ = tab.applyCachedFaviconOrPlaceholder(for: shortcutState.url)

        if tab.existingWebView != nil {
            tab.loadURL(shortcutState.url)
        }
    }

    @discardableResult
    private func restoreShortcutLauncher(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState? = nil
    ) -> ShortcutPin? {
        if let existing = tabManager.shortcutPin(by: pinState.id) {
            return existing
        }

        let restoredPin: ShortcutPin?
        switch pinState.role {
        case .essential:
            guard let profileId = restoredEssentialProfileId(
                from: pinState,
                fallbackWindow: fallbackWindow
            ) else {
                return nil
            }
            restoredPin = ShortcutPin(
                id: pinState.id,
                role: .essential,
                profileId: profileId,
                executionProfileId: pinState.executionProfileId,
                spaceId: nil,
                index: pinState.index,
                folderId: nil,
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset
            )
        case .spacePinned:
            guard let spaceId = restoredSpacePinnedSpaceId(
                from: pinState,
                fallbackWindow: fallbackWindow
            ) else {
                return nil
            }
            let folderId = pinState.folderId.flatMap { folderId in
                tabManager.folderSpaceId(for: folderId) == spaceId ? folderId : nil
            }
            restoredPin = ShortcutPin(
                id: pinState.id,
                role: .spacePinned,
                profileId: nil,
                executionProfileId: pinState.executionProfileId,
                spaceId: spaceId,
                index: pinState.index,
                folderId: folderId,
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset
            )
        }

        guard let restoredPin,
              let inserted = tabManager.insertShortcutPin(restoredPin, at: pinState.index)
        else {
            return nil
        }
        tabManager.scheduleStructuralPersistence()
        return inserted
    }

    private func restoredEssentialProfileId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        if let profileId = pinState.profileId,
           profileManager.profiles.contains(where: { $0.id == profileId }) {
            return profileId
        }
        if let profileId = fallbackWindow?.currentProfileId,
           profileManager.profiles.contains(where: { $0.id == profileId }) {
            return profileId
        }
        if let profileId = currentProfile?.id,
           profileManager.profiles.contains(where: { $0.id == profileId }) {
            return profileId
        }
        return profileManager.profiles.first?.id
    }

    private func restoredSpacePinnedSpaceId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        if let spaceId = pinState.spaceId,
           tabManager.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           tabManager.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = tabManager.currentSpace?.id,
           tabManager.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        return tabManager.spaces.first?.id
    }

    func reopenWindow(from snapshot: WindowSessionSnapshot) async {
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

    func currentRegularWindowSnapshots(
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
