import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserActivePageRoutingOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let activePreviewTab: @MainActor (BrowserWindowState) -> Tab?
        let activePreviewWebView: @MainActor (BrowserWindowState) -> WKWebView?
        let activeSessionURL: @MainActor (BrowserWindowState) -> URL?
        let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
        let refreshActivePage: @MainActor (Tab, BrowserWindowState) -> Void
        let createNewTab: @MainActor (BrowserWindowState, String) -> Void
        let openNewTab: @MainActor (String, BrowserTabOpenContext) -> Tab?
        let containsSpace: @MainActor (UUID) -> Bool
        let folderSpaceId: @MainActor (UUID) -> UUID?
        let resolveEssentialsInsertion:
            @MainActor (BrowserWindowState, Int) -> TabManager.EssentialsInsertionPlan?
        let convertTabToShortcutPin:
            @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int, Bool) -> ShortcutPin?
        let presentCopyToast: @MainActor (BrowserWindowState) -> Void
        let writeURLToPasteboard: @MainActor (String) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func currentTabForActiveWindow() -> Tab? {
        guard let activeWindow = dependencies.activeWindow() else { return nil }
        return dependencies.currentTab(activeWindow)
    }

    func activePageTab(for windowState: BrowserWindowState) -> Tab? {
        dependencies.activePreviewTab(windowState)
            ?? dependencies.currentTab(windowState)
    }

    func activePageTabForActiveWindow() -> Tab? {
        guard let activeWindow = dependencies.activeWindow() else { return nil }
        return activePageTab(for: activeWindow)
    }

    func activePageWebView(for windowState: BrowserWindowState) -> WKWebView? {
        if let previewTab = dependencies.activePreviewTab(windowState) {
            return dependencies.windowOwnedWebView(previewTab, windowState.id)
                ?? dependencies.activePreviewWebView(windowState)
        }

        guard let tab = dependencies.currentTab(windowState) else { return nil }
        return dependencies.windowOwnedWebView(tab, windowState.id)
    }

    func activePageWebViewForActiveWindow() -> WKWebView? {
        guard let activeWindow = dependencies.activeWindow() else { return nil }
        return activePageWebView(for: activeWindow)
    }

    func activePageURL(for windowState: BrowserWindowState) -> URL? {
        dependencies.activeSessionURL(windowState)
            ?? activePageTab(for: windowState)?.url
    }

    func activePageURLForActiveWindow() -> URL? {
        guard let activeWindow = dependencies.activeWindow() else { return nil }
        return activePageURL(for: activeWindow)
    }

    func refreshCurrentTabInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow(),
              let tab = activePageTab(for: activeWindow)
        else {
            return
        }
        dependencies.refreshActivePage(tab, activeWindow)
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

            Task { @MainActor [weak self] in
                guard let self else { return }
                let success = self.dependencies.writeURLToPasteboard(url)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
                RuntimeDiagnostics.emit("Clipboard operation success: \(success)")
            }

            if let windowState = dependencies.activeWindow() {
                dependencies.presentCopyToast(windowState)
            }
        } else {
            RuntimeDiagnostics.emit("No URL found to copy")
        }
    }

    func openWebInspector() {
        guard RuntimeDiagnostics.isDeveloperInspectionEnabled else {
            RuntimeDiagnostics.emit("Developer inspection is disabled for this runtime.")
            return
        }

        guard let activeWindow = dependencies.activeWindow() else {
            RuntimeDiagnostics.emit("No active window to inspect")
            return
        }

        guard let tab = activePageTab(for: activeWindow),
              let webView = dependencies.windowOwnedWebView(tab, activeWindow.id)
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

        guard let webView = dependencies.windowOwnedWebView(tab, windowState.id) else {
            RuntimeDiagnostics.emit("No window-owned web view available to inspect")
            return
        }

        inspect(webView)
    }

    func presentExternalURL(_ url: URL) {
        guard let windowState = dependencies.activeWindow() else { return }
        dependencies.createNewTab(windowState, url.absoluteString)
    }

    @discardableResult
    func openDroppedURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        at slot: DropZoneSlot
    ) -> Bool {
        guard slot != .empty else { return false }

        if windowState.isIncognito {
            return dependencies.openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState)
            ) != nil
        }

        switch slot {
        case .spaceRegular(let spaceId, let index):
            guard dependencies.containsSpace(spaceId) else { return false }
            return dependencies.openNewTab(
                url.absoluteString,
                .foreground(
                    windowState: windowState,
                    preferredSpaceId: spaceId,
                    regularInsertionIndex: index
                )
            ) != nil

        case .spacePinned(let spaceId, let index):
            guard dependencies.containsSpace(spaceId) else { return false }
            guard let tab = dependencies.openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState, preferredSpaceId: spaceId)
            ) else { return false }
            return dependencies.convertTabToShortcutPin(
                tab,
                .spacePinned,
                nil,
                spaceId,
                nil,
                index,
                true
            ) != nil

        case .folder(let folderId, let index):
            guard let spaceId = dependencies.folderSpaceId(folderId) else { return false }
            guard let tab = dependencies.openNewTab(
                url.absoluteString,
                .foreground(windowState: windowState, preferredSpaceId: spaceId)
            ) else { return false }
            return dependencies.convertTabToShortcutPin(
                tab,
                .spacePinned,
                nil,
                spaceId,
                folderId,
                index,
                false
            ) != nil

        case .essentials(let index):
            let insertion = dependencies.resolveEssentialsInsertion(windowState, index)
            guard let insertion else { return false }
            guard let tab = dependencies.openNewTab(
                url.absoluteString,
                .foreground(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            ) else { return false }
            return dependencies.convertTabToShortcutPin(
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
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func inspect(_ webView: WKWebView) {
        webView.isInspectable = true
        showWebInspectorAlert()
    }
}

extension BrowserActivePageRoutingOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            activePreviewTab: { [weak browserManager] windowState in
                browserManager?.glanceManager.activePreviewTab(for: windowState)
            },
            activePreviewWebView: { [weak browserManager] windowState in
                browserManager?.glanceManager.activePreviewWebView(for: windowState)
            },
            activeSessionURL: { [weak browserManager] windowState in
                browserManager?.glanceManager.activeSession(for: windowState)?.currentURL
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            },
            refreshActivePage: { [weak browserManager] tab, windowState in
                browserManager?.refreshWindowScopedPage(
                    tab: tab,
                    in: windowState,
                    reason: "BrowserActivePage.refresh"
                )
            },
            createNewTab: { [weak browserManager] windowState, urlString in
                browserManager?.createNewTab(in: windowState, url: urlString)
            },
            openNewTab: { [weak browserManager] urlString, context in
                browserManager?.openNewTab(url: urlString, context: context)
            },
            containsSpace: { [weak browserManager] spaceId in
                browserManager?.tabManager.spaces.contains { $0.id == spaceId } == true
            },
            folderSpaceId: { [weak browserManager] folderId in
                browserManager?.tabManager.folderSpaceId(for: folderId)
            },
            resolveEssentialsInsertion: { [weak browserManager] windowState, index in
                browserManager?.tabManager.resolveEssentialsInsertion(
                    using: TabManager.EssentialsInsertionContext(
                        target: TabManager.EssentialsTargetContext(windowState: windowState),
                        targetIndex: index
                    )
                )
            },
            convertTabToShortcutPin: { [weak browserManager] tab, role, profileId, spaceId, folderId, index, openTargetFolder in
                browserManager?.tabManager.convertTabToShortcutPin(
                    tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    at: index,
                    openTargetFolder: openTargetFolder
                )
            },
            presentCopyToast: { [weak browserManager] windowState in
                browserManager?.presentToast(.init(kind: .copyURL), in: windowState)
            },
            writeURLToPasteboard: { urlString in
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(urlString, forType: .string)
            }
        )
    }
}
