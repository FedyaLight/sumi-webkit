//
//  BrowserManager+DialogsUtilities.swift
//  Sumi
//
//

import AppKit
import WebKit

@MainActor
extension BrowserManager {
    // MARK: - Native Modal Presentation

    func requestCollapsedSidebarOverlayDismissal() {
        nativeDialogPresentationOwner.requestCollapsedSidebarOverlayDismissal()
    }

    func showQuitDialog() {
        nativeDialogPresentationOwner.showQuitDialog()
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        nativeDialogPresentationOwner.presentBrowsingDataSheet(windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        nativeDialogPresentationOwner.presentBasicAuthSheet(session, in: windowState)
    }

    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) {
        nativeDialogPresentationOwner.presentNoticeSheet(notice, source: source)
    }

    func dismissNativeModalPresentation() {
        nativeDialogPresentationOwner.dismissNativeModalPresentation()
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        nativeDialogPresentationOwner.nativeModalPresentationBindingDismissed(for: windowID)
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        nativeDialogPresentationOwner.isNativeModalPresented(in: windowID)
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        nativeDialogPresentationOwner.isNativeModalPresented(in: window)
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        nativeDialogPresentationOwner.presentSharingServicePicker(items, source: source)
    }

    func cleanupAllTabs() {
        RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up all tabs")
        extensionsModule.cancelNativeMessagingSessionsIfLoaded(
            reason: "BrowserManager.cleanupAllTabs"
        )
        extensionsModule.closeAllOptionsWindowsIfLoaded()
        auxiliaryWindowManager.closeAll(reason: .appQuit)
        glanceManager.dismissGlance(persistsWindowSession: false)

        var seenTabIDs = Set<UUID>()
        var allTabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            allTabs.append(tab)
        }

        tabManager.allPinnedTabsAllProfiles.forEach(append)
        tabManager.allTabs().forEach(append)
        windowRegistry?.allWindows
            .flatMap(\.ephemeralTabs)
            .forEach(append)

        for tab in allTabs {
            RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up tab: \(tab.name)")
            tab.cleanupNormalTabPermissionRuntime(reason: "browser-manager-cleanup-all-tabs")
            tab.performComprehensiveWebViewCleanup()
        }

        webViewCoordinator?.cleanupAllWebViews(tabManager: tabManager)
    }

    // MARK: - Window-Aware Tab Operations for Commands

    func currentTabForActiveWindow() -> Tab? {
        if let activeWindow = windowRegistry?.activeWindow {
            return currentTab(for: activeWindow)
        }
        return tabManager.currentTab
    }

    func activePageTab(for windowState: BrowserWindowState) -> Tab? {
        glanceManager.activePreviewTab(for: windowState)
            ?? currentTab(for: windowState)
    }

    func activePageTabForActiveWindow() -> Tab? {
        if let activeWindow = windowRegistry?.activeWindow {
            return activePageTab(for: activeWindow)
        }
        return tabManager.currentTab
    }

    func activePageWebView(for windowState: BrowserWindowState) -> WKWebView? {
        guard let tab = activePageTab(for: windowState) else { return nil }
        return tab.existingWebView ?? getWebView(for: tab.id, in: windowState.id)
    }

    func activePageWebViewForActiveWindow() -> WKWebView? {
        guard let activeWindow = windowRegistry?.activeWindow else { return nil }
        return activePageWebView(for: activeWindow)
    }

    func activePageURL(for windowState: BrowserWindowState) -> URL? {
        glanceManager.activeSession(for: windowState)?.currentURL
            ?? activePageTab(for: windowState)?.url
    }

    func activePageURLForActiveWindow() -> URL? {
        guard let activeWindow = windowRegistry?.activeWindow else {
            return tabManager.currentTab?.url
        }
        return activePageURL(for: activeWindow)
    }

    func refreshCurrentTabInActiveWindow() {
        activePageTabForActiveWindow()?.refresh()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        activePageTabForActiveWindow()?.toggleMute()
    }

    func currentTabIsMuted() -> Bool {
        activePageTabForActiveWindow()?.audioState.isMuted ?? false
    }

    func currentTabHasAudioContent() -> Bool {
        activePageTabForActiveWindow()?.audioState.isPlayingAudio ?? false
    }

    // MARK: - URL Utilities

    func copyCurrentURL() {
        if let url = activePageURLForActiveWindow()?.absoluteString {
            RuntimeDiagnostics.emit("Attempting to copy URL: \(url)")

            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(url, forType: .string)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
                RuntimeDiagnostics.emit("Clipboard operation success: \(success)")
            }

            if let windowState = windowRegistry?.activeWindow {
                presentToast(.init(kind: .copyURL), in: windowState)
            }
        } else {
            RuntimeDiagnostics.emit("No URL found to copy")
        }
    }

    // MARK: - Web Inspector

    func openWebInspector() {
        guard RuntimeDiagnostics.isDeveloperInspectionEnabled else {
            RuntimeDiagnostics.emit("Developer inspection is disabled for this runtime.")
            return
        }

        guard let currentTab = activePageTabForActiveWindow() else {
            RuntimeDiagnostics.emit("No current tab to inspect")
            return
        }

        guard let webView = currentTab.ensureWebView() else {
            RuntimeDiagnostics.emit("No web view available to inspect")
            return
        }

        webView.isInspectable = true
        showWebInspectorAlert()
    }

    // MARK: - Profile Switch Toast

    func showProfileSwitchToast(to: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        presentToast(.init(kind: .profileSwitch(profileName: to.name)), in: targetWindow)
    }

    func presentToast(_ toast: BrowserToast, in windowState: BrowserWindowState? = nil) {
        guard sumiSettings?.showBrowserToasts != false else { return }
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        targetWindow.presentToast(toast)
    }

    // MARK: - External URL Routing

    func presentExternalURL(_ url: URL) {
        guard let windowState = windowRegistry?.activeWindow else { return }
        createNewTab(in: windowState, url: url.absoluteString)
    }

    @discardableResult
    func openDroppedURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        at slot: DropZoneSlot
    ) -> Bool {
        guard slot != .empty else { return false }

        if windowState.isIncognito {
            _ = openNewTab(
                url: url.absoluteString,
                context: .foreground(windowState: windowState)
            )
            return true
        }

        switch slot {
        case .spaceRegular(let spaceId, let index):
            guard tabManager.spaces.contains(where: { $0.id == spaceId }) else { return false }
            _ = openNewTab(
                url: url.absoluteString,
                context: .foreground(
                    windowState: windowState,
                    preferredSpaceId: spaceId,
                    regularInsertionIndex: index
                )
            )
            return true

        case .spacePinned(let spaceId, let index):
            guard tabManager.spaces.contains(where: { $0.id == spaceId }) else { return false }
            let tab = openNewTab(
                url: url.absoluteString,
                context: .foreground(windowState: windowState, preferredSpaceId: spaceId)
            )
            return tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: index
            ) != nil

        case .folder(let folderId, let index):
            guard let spaceId = tabManager.folderSpaceId(for: folderId) else { return false }
            let tab = openNewTab(
                url: url.absoluteString,
                context: .foreground(windowState: windowState, preferredSpaceId: spaceId)
            )
            return tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: folderId,
                at: index,
                openTargetFolder: false
            ) != nil

        case .essentials(let index):
            let insertion = tabManager.resolveEssentialsInsertion(
                using: TabManager.EssentialsInsertionContext(
                    target: TabManager.EssentialsTargetContext(windowState: windowState),
                    targetIndex: index
                )
            )
            guard let insertion else { return false }
            let tab = openNewTab(
                url: url.absoluteString,
                context: .foreground(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            )
            return tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: insertion.profileId,
                spaceId: nil,
                folderId: nil,
                at: insertion.index
            ) != nil

        case .empty:
            return false
        }
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
