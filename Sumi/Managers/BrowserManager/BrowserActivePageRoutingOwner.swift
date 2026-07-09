import AppKit
import Foundation
import WebKit
import SumiDomain

@MainActor
final class BrowserActivePageRoutingOwner {
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let activePreviewTab: @MainActor (BrowserWindowState) -> Tab?
    private let activePreviewWebView: @MainActor (BrowserWindowState) -> WKWebView?
    private let activeSessionURL: @MainActor (BrowserWindowState) -> URL?
    private let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
    private let refreshActivePage: @MainActor (Tab, BrowserWindowState) -> Void
    private let createNewTab: @MainActor (BrowserWindowState, String) -> Void
    private let openNewTab: @MainActor (String, BrowserTabOpenContext) -> Tab?
    private let containsSpace: @MainActor (UUID) -> Bool
    private let folderSpaceId: @MainActor (UUID) -> UUID?
    private let resolveEssentialsInsertion:
        @MainActor (BrowserWindowState, Int) -> EssentialsShortcutPlacementOwner.InsertionPlan?
    private let convertTabToShortcutPin:
        @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?
    private let copyURLToPasteboard: @MainActor (String, BrowserWindowState?) -> Bool

    init(
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        activePreviewTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        activePreviewWebView: @escaping @MainActor (BrowserWindowState) -> WKWebView?,
        activeSessionURL: @escaping @MainActor (BrowserWindowState) -> URL?,
        windowOwnedWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?,
        refreshActivePage: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        createNewTab: @escaping @MainActor (BrowserWindowState, String) -> Void,
        openNewTab: @escaping @MainActor (String, BrowserTabOpenContext) -> Tab?,
        containsSpace: @escaping @MainActor (UUID) -> Bool,
        folderSpaceId: @escaping @MainActor (UUID) -> UUID?,
        resolveEssentialsInsertion: @escaping @MainActor (BrowserWindowState, Int) -> EssentialsShortcutPlacementOwner.InsertionPlan?,
        convertTabToShortcutPin: @escaping @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?,
        copyURLToPasteboard: @escaping @MainActor (String, BrowserWindowState?) -> Bool
    ) {
        self.activeWindow = activeWindow
        self.currentTab = currentTab
        self.activePreviewTab = activePreviewTab
        self.activePreviewWebView = activePreviewWebView
        self.activeSessionURL = activeSessionURL
        self.windowOwnedWebView = windowOwnedWebView
        self.refreshActivePage = refreshActivePage
        self.createNewTab = createNewTab
        self.openNewTab = openNewTab
        self.containsSpace = containsSpace
        self.folderSpaceId = folderSpaceId
        self.resolveEssentialsInsertion = resolveEssentialsInsertion
        self.convertTabToShortcutPin = convertTabToShortcutPin
        self.copyURLToPasteboard = copyURLToPasteboard
    }

    func currentTabForActiveWindow() -> Tab? {
        guard let activeWindow = activeWindow() else { return nil }
        return currentTab(activeWindow)
    }

    func activePageTab(for windowState: BrowserWindowState) -> Tab? {
        activePreviewTab(windowState)
            ?? currentTab(windowState)
    }

    func activePageTabForActiveWindow() -> Tab? {
        guard let activeWindow = activeWindow() else { return nil }
        return activePageTab(for: activeWindow)
    }

    func activePageWebView(for windowState: BrowserWindowState) -> WKWebView? {
        if let previewTab = activePreviewTab(windowState) {
            return windowOwnedWebView(previewTab, windowState.id)
                ?? activePreviewWebView(windowState)
        }

        guard let tab = currentTab(windowState) else { return nil }
        return windowOwnedWebView(tab, windowState.id)
    }

    func activePageWebViewForActiveWindow() -> WKWebView? {
        guard let activeWindow = activeWindow() else { return nil }
        return activePageWebView(for: activeWindow)
    }

    func activePageURL(for windowState: BrowserWindowState) -> URL? {
        activeSessionURL(windowState)
            ?? activePageTab(for: windowState)?.url
    }

    func activePageURLForActiveWindow() -> URL? {
        guard let activeWindow = activeWindow() else { return nil }
        return activePageURL(for: activeWindow)
    }

    func refreshCurrentTabInActiveWindow() {
        guard let activeWindow = activeWindow(),
              let tab = activePageTab(for: activeWindow)
        else {
            return
        }
        refreshActivePage(tab, activeWindow)
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

    func copyCurrentURL() {
        if let url = activePageURLForActiveWindow()?.absoluteString {
            RuntimeDiagnostics.emit("Attempting to copy URL: \(url)")

            let windowState = activeWindow()
            let success = copyURLToPasteboard(url, windowState)
            if success {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
            }
            RuntimeDiagnostics.emit("Clipboard operation success: \(success)")
        } else {
            RuntimeDiagnostics.emit("No URL found to copy")
        }
    }

    func activeFindSession() -> (tab: Tab?, windowId: UUID?) {
        guard let windowState = activeWindow() else {
            return (nil, nil)
        }
        return (activePageTab(for: windowState), windowState.id)
    }

    func openWebInspector() {
        guard RuntimeDiagnostics.isDeveloperInspectionEnabled else {
            RuntimeDiagnostics.emit("Developer inspection is disabled for this runtime.")
            return
        }

        guard let activeWindow = activeWindow() else {
            RuntimeDiagnostics.emit("No active window to inspect")
            return
        }

        guard let tab = activePageTab(for: activeWindow),
              let webView = windowOwnedWebView(tab, activeWindow.id)
        else {
            RuntimeDiagnostics.emit("No window-owned web view available to inspect")
            return
        }

        inspect(webView)
    }

    func openWebInspector(for tab: Tab, in windowState: BrowserWindowState) {
        guard RuntimeDiagnostics.isDeveloperInspectionEnabled else {
            RuntimeDiagnostics.emit("Developer inspection is disabled for this runtime.")
            return
        }

        guard let webView = windowOwnedWebView(tab, windowState.id) else {
            RuntimeDiagnostics.emit("No window-owned web view available to inspect")
            return
        }

        inspect(webView)
    }

    func presentExternalURL(_ url: URL) {
        guard let windowState = activeWindow() else { return }
        createNewTab(windowState, url.absoluteString)
    }

    @discardableResult
    func openDroppedURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        at slot: DropZoneSlot
    ) -> Bool {
        guard slot != .empty else { return false }

        if windowState.isIncognito {
            return openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState)
            ) != nil
        }

        switch slot {
        case .spaceRegular(let spaceId, let index):
            guard containsSpace(spaceId) else { return false }
            return openNewTab(
                url.absoluteString,
                .foreground(
                    windowState: windowState,
                    preferredSpaceId: spaceId,
                    regularInsertionIndex: index
                )
            ) != nil

        case .spacePinned(let spaceId, let index):
            guard containsSpace(spaceId) else { return false }
            guard let tab = openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState, preferredSpaceId: spaceId)
            ) else { return false }
            return convertTabToShortcutPin(
                tab,
                .spacePinned,
                nil,
                spaceId,
                nil,
                index,
                true
            ) != nil

        case .folder(let folderId, let index):
            guard let spaceId = folderSpaceId(folderId) else { return false }
            guard let tab = openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState, preferredSpaceId: spaceId)
            ) else { return false }
            return convertTabToShortcutPin(
                tab,
                .spacePinned,
                nil,
                spaceId,
                folderId,
                index,
                false
            ) != nil

        case .essentials(let index):
            let insertion = resolveEssentialsInsertion(windowState, index)
            guard let insertion else { return false }
            guard let tab = openNewTab(
                url.absoluteString,
                .foreground(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            ) else { return false }
            return convertTabToShortcutPin(
                tab,
                .essential,
                insertion.profileId,
                nil,
                nil,
                insertion.index,
                true
            ) != nil

        case .empty:
            return false
        }
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n"
            + "1. Right-click on the page and select 'Inspect Element'\n\n"
            + "Or enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func inspect(_ webView: WKWebView) {
        webView.isInspectable = true
        showWebInspectorAlert()
    }
}
