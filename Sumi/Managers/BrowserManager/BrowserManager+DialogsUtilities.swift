//
//  BrowserManager+DialogsUtilities.swift
//  Sumi
//
//

import AppKit
import SwiftUI
import WebKit

@MainActor
private final class SidebarSharingServicePickerRetainer {
    static let shared = SidebarSharingServicePickerRetainer()

    private var bridges: [ObjectIdentifier: SidebarSharingServicePickerBridge] = [:]

    func retain(_ bridge: SidebarSharingServicePickerBridge) {
        bridges[ObjectIdentifier(bridge)] = bridge
    }

    func release(_ bridge: SidebarSharingServicePickerBridge) {
        bridges.removeValue(forKey: ObjectIdentifier(bridge))
    }
}

@MainActor
private final class SidebarSharingServicePickerBridge: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    private let token: SidebarTransientSessionToken
    private weak var coordinator: SidebarTransientSessionCoordinator?
    private var hasFinished = false

    init(
        token: SidebarTransientSessionToken,
        coordinator: SidebarTransientSessionCoordinator
    ) {
        self.token = token
        self.coordinator = coordinator
        super.init()
        SidebarSharingServicePickerRetainer.shared.retain(self)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        finish()
    }

    func scheduleFallbackFinish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        coordinator?.finishSession(
            token,
            reason: "SidebarSharingServicePickerBridge.finish"
        )
        SidebarSharingServicePickerRetainer.shared.release(self)
    }
}

@MainActor
extension BrowserManager {
    private func modalPresentationWindow(
        for source: SidebarTransientPresentationSource? = nil
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? windowRegistry?.activeWindow?.window
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
    }

    // MARK: - Native Modal Presentation

    func requestCollapsedSidebarOverlayDismissal() {
        NotificationCenter.default.post(
            name: .sumiShouldHideCollapsedSidebarOverlay,
            object: self
        )
    }

    func showQuitDialog() {
        requestCollapsedSidebarOverlayDismissal()
        dismissFloatingBarForActiveWindow(preserveDraft: true)
        NSApplication.shared.terminate(nil)
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        _ = presentNativeModal(.browsingData, windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        presentNativeModal(
            .basicAuth(session),
            windowState: windowState,
            onDismiss: {
                session.cancel()
            }
        )
    }

    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) {
        _ = presentNativeModal(.notice(notice), source: source)
    }

    func dismissNativeModalPresentation() {
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.dismissNativeModalPresentation",
            invokeOnDismiss: false
        )
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        dismissNativeModalPresentation(
            for: windowID,
            reason: "BrowserManager.nativeModalPresentationBindingDismissed",
            invokeOnDismiss: true
        )
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        guard let presentation = nativeModalPresentation else { return false }
        guard let windowID else { return true }
        return presentation.windowID == windowID
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        guard let presentation = nativeModalPresentation else { return false }
        guard let window else { return true }
        if let presentedWindow = presentation.window {
            return presentedWindow === window
        }
        return windowRegistry?.windows[presentation.windowID]?.window === window
    }

    private func prepareForNativeModalPresentation() {
        requestCollapsedSidebarOverlayDismissal()
        dismissWorkspaceThemePickerIfNeededDiscarding()
    }

    @discardableResult
    private func presentNativeModal(
        _ kind: BrowserNativeModalKind,
        windowState: BrowserWindowState? = nil,
        source: SidebarTransientPresentationSource? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        prepareForNativeModalPresentation()
        dismissNativeModalPresentation(
            for: nil,
            reason: "BrowserManager.presentNativeModalReplacingExisting",
            invokeOnDismiss: true
        )

        let targetWindowState = windowState ?? windowRegistry?.activeWindow
        let windowID = source?.windowID ?? targetWindowState?.id
        guard let windowID else { return false }

        let window = source?.window?.parent
            ?? source?.window
            ?? targetWindowState?.window
            ?? modalPresentationWindow(for: source)
        let transientSessionToken: SidebarTransientSessionToken?
        if let source {
            transientSessionToken = source.coordinator?.beginSession(
                kind: .dialog,
                source: source,
                path: "BrowserManager.presentNativeModal"
            )
        } else {
            transientSessionToken = nil
        }

        nativeModalPresentation = BrowserNativeModalPresentation(
            windowID: windowID,
            window: window,
            kind: kind,
            source: source,
            transientSessionToken: transientSessionToken,
            onDismiss: onDismiss
        )
        return true
    }

    private func dismissNativeModalPresentation(
        for windowID: UUID?,
        reason: String,
        invokeOnDismiss: Bool
    ) {
        guard let presentation = nativeModalPresentation else { return }
        guard windowID == nil || presentation.windowID == windowID else { return }

        nativeModalPresentation = nil

        if let transientSessionToken = presentation.transientSessionToken,
           let coordinator = presentation.source?.coordinator
        {
            coordinator.finishSession(
                transientSessionToken,
                reason: reason
            )
        } else {
            SidebarHostRecoveryCoordinator.shared.recover(in: presentation.window)
        }

        if invokeOnDismiss {
            presentation.onDismiss?()
        }
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        guard let contentView = source.window?.contentView ?? modalPresentationWindow(for: source)?.contentView else {
            return
        }

        let picker = NSSharingServicePicker(items: items)
        let bridge = source.coordinator.flatMap {
            SidebarSharingServicePickerBridge(
                token: $0.beginSession(
                    kind: .sharingPicker,
                    source: source,
                    path: "BrowserManager.presentSharingServicePicker"
                ),
                coordinator: $0
            )
        }
        picker.delegate = bridge

        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        bridge?.scheduleFallbackFinish()
    }

    func cleanupAllTabs() {
        RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up all tabs")
        extensionsModule.cancelNativeMessagingSessionsIfLoaded(
            reason: "BrowserManager.cleanupAllTabs"
        )
        extensionsModule.closeAllOptionsWindowsIfLoaded()
        externalMiniWindowManager.closeAll()
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
