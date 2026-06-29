//
//  BrowserManager+History.swift
//  Sumi
//

import AppKit

@MainActor
extension BrowserManager {
    enum HistoryOpenMode {
        case currentTab
        case newTab
        case newWindow
    }

    var canOfferStartupLastSessionRestoreShortcut: Bool {
        startupSessionRestoreOwner.canOfferRestoreShortcut
    }

    var canRestoreAnyLastSession: Bool {
        canOfferStartupLastSessionRestoreShortcut || lastSessionWindowsStore.canRestoreLastSession
    }

    var canGoBackInActiveWindow: Bool {
        historyNavigationOwner.canGoBackInActiveWindow
    }

    var canGoForwardInActiveWindow: Bool {
        historyNavigationOwner.canGoForwardInActiveWindow
    }

    func goBackInActiveWindow() {
        historyNavigationOwner.goBackInActiveWindow()
    }

    func goForwardInActiveWindow() {
        historyNavigationOwner.goForwardInActiveWindow()
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        historyNavigationOwner.openHistoryTab(selecting: range, in: windowState)
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        historyNavigationOwner.openHistoryURLFromMenuItem(url)
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: HistoryOpenMode
    ) {
        historyNavigationOwner.openHistoryURL(url, in: windowState, preferredOpenMode: preferredOpenMode)
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        historyNavigationOwner.openURLsInNewTabs(urls, in: windowState)
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        historyNavigationOwner.openHistoryURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
        historyNavigationOwner.openURLsInNewWindow(urls)
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        historyNavigationOwner.openHistoryURLsInNewWindow(urls)
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
        startupSessionRestoreOwner.markRestoreOfferConsumed()
    }

    func reopenAllWindowsFromLastSession() {
        let useStartupArchive = canOfferStartupLastSessionRestoreShortcut
        let sourceSnapshots = useStartupArchive
            ? startupSessionRestoreOwner.windowSnapshots
            : lastSessionWindowsStore.snapshots
        let sourceTabSnapshot = useStartupArchive
            ? (startupSessionRestoreOwner.tabSnapshot ?? lastSessionWindowsStore.tabSnapshot)
            : lastSessionWindowsStore.tabSnapshot
        let existingSessions = Set(currentRegularWindowSnapshots(excludingWindowID: nil).map(\.session))
        let snapshotsToRestore = sourceSnapshots.filter { !existingSessions.contains($0.session) }
        guard !snapshotsToRestore.isEmpty else { return }

        startupSessionRestoreOwner.markRestoreOfferConsumed()
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
        windowHistorySessionOwner.handleWindowWillClose(windowId)
    }

    func refreshLastSessionWindowsStore(excludingWindowID: UUID?) {
        windowHistorySessionOwner.refreshLastSessionWindowsStore(excludingWindowID: excludingWindowID)
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
        windowHistorySessionOwner.currentRegularWindowSnapshots(excludingWindowID: excludingWindowID)
    }

    func windowDisplayTitle(for windowState: BrowserWindowState) -> String {
        if let currentTab = currentTab(for: windowState) {
            return currentTab.name
        }
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace.name
        }
        return "Window"
    }
}
