import AppKit
import Foundation
import WebKit

/// Adapts browser windows, tabs, and auxiliary windows to the WebExtension
/// bridge protocol. Replaces the former god-object conformance of
/// `BrowserManager` to `ExtensionBrowserBridgeContext`.
@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionBridgeAdapter {
    struct Dependencies {
        let windowRegistry: @MainActor () -> WindowRegistry?
        let tabManager: @MainActor () -> TabManager?
        let auxiliaryWindowManager: @MainActor () -> AuxiliaryWindowManager?
        let webViewCoordinator: @MainActor () -> WebViewCoordinator?
        let tabsForWebExtensionWindow: @MainActor (BrowserWindowState) -> [Tab]
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let currentTabForActiveWindow: @MainActor () -> Tab?
        let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
        let materializeVisibleTabWebViewIfNeeded: @MainActor (Tab, BrowserWindowState) -> Void
        let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
        let createNewWindow: @MainActor () -> Void
        let urlBarHubAnchorView: @MainActor (UUID) -> NSView?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    private var windowRegistry: WindowRegistry? {
        dependencies.windowRegistry()
    }

    private var tabManager: TabManager? {
        dependencies.tabManager()
    }

    private var auxiliaryWindowManager: AuxiliaryWindowManager? {
        dependencies.auxiliaryWindowManager()
    }

    private func requireTabManager(operation: String) -> TabManager {
        guard let tabManager else {
            preconditionFailure(
                "BrowserManager was released before the extension bridge could \(operation)."
            )
        }
        return tabManager
    }
}

@available(macOS 15.5, *)
extension BrowserExtensionBridgeAdapter: ExtensionBrowserBridgeContext {
    func extensionWindowState(for windowId: UUID) -> BrowserWindowState? {
        windowRegistry?.windows[windowId]
    }

    var activeExtensionWindowState: BrowserWindowState? {
        windowRegistry?.activeWindow
    }

    var allExtensionWindowStates: [BrowserWindowState] {
        windowRegistry?.allWindows ?? []
    }

    func extensionTab(for tabId: UUID) -> Tab? {
        if let tab = tabManager?.tab(for: tabId) {
            return tab
        }

        guard let windowStates = windowRegistry?.windows.values else {
            return nil
        }
        for windowState in windowStates {
            if let tab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                return tab
            }
        }
        return nil
    }

    func extensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        dependencies.windowStateContainingTab(tab)
    }

    func extensionWindowState(forAppKitWindow window: NSWindow) -> BrowserWindowState? {
        windowRegistry?.windows.values.first { $0.window === window }
    }

    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab? {
        dependencies.currentTab(windowState)
    }

    func currentExtensionTabForActiveWindow() -> Tab? {
        dependencies.currentTabForActiveWindow()
    }

    func currentExtensionTabForPopup() -> Tab? {
        dependencies.currentTabForActiveWindow()
    }

    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab] {
        dependencies.tabsForWebExtensionWindow(windowState)
    }

    func extensionSpace(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager?.spaces.first { $0.id == spaceId }
    }

    func extensionTargetSpace(for windowState: BrowserWindowState?) -> Space? {
        guard let windowState else { return nil }

        if let currentSpaceId = windowState.currentSpaceId,
           let currentSpace = extensionSpace(for: currentSpaceId),
           windowState.currentProfileId.map({ currentSpace.profileId == $0 }) ?? true {
            return currentSpace
        }

        if let profileId = windowState.currentProfileId,
           let profileSpace = tabManager?.spaces.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        return nil
    }

    func extensionTargetSpace(for tab: Tab) -> Space? {
        tab.spaceId.flatMap(extensionSpace(for:))
    }

    func extensionTargetSpace(matchingProfile profileId: UUID) -> Space? {
        tabManager?.spaces.first { $0.profileId == profileId }
    }

    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        if let primaryWindowId = tab.primaryWindowId,
           let primaryWindow = windowRegistry?.windows[primaryWindowId] {
            return primaryWindow
        }

        if let containing = dependencies.windowStateContainingTab(tab) {
            return containing
        }

        if let spaceId = tab.spaceId,
           let displayingSpaceWindow = extensionWindowState(displayingSpaceId: spaceId) {
            return displayingSpaceWindow
        }

        if let activeWindow = activeExtensionWindowState,
           tabsForExtensionWindow(activeWindow).contains(where: { $0.id == tab.id }) {
            return activeWindow
        }

        return windowRegistry?.allWindows.sorted { $0.id.uuidString < $1.id.uuidString }.first { windowState in
            tabsForExtensionWindow(windowState).contains(where: { $0.id == tab.id })
        }
    }

    private func extensionWindowState(displayingSpaceId spaceId: UUID) -> BrowserWindowState? {
        let activeWindow = activeExtensionWindowState
        if let activeWindow,
           activeWindow.currentSpaceId == spaceId {
            return activeWindow
        }
        let activeWindowId = activeWindow?.id

        return windowRegistry?.allWindows
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { windowState in
                windowState.id != activeWindowId
                    && windowState.currentSpaceId == spaceId
            }
    }

    func setActiveExtensionWindow(_ windowState: BrowserWindowState) {
        windowRegistry?.setActive(windowState)
    }

    func createExtensionWindow() {
        dependencies.createNewWindow()
    }

    func awaitNextExtensionWindow(excluding existingWindowIDs: Set<UUID>) async -> BrowserWindowState? {
        await windowRegistry?.awaitNextRegisteredWindow(excluding: existingWindowIDs)
    }

    func createExtensionTab(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let tabManager = requireTabManager(operation: "create a tab")
        if let url {
            return tabManager.createNewTab(
                url: url.absoluteString,
                in: space,
                activate: activate,
                webExtensionContextOverride: webExtensionContextOverride
            )
        }

        return tabManager.createNewTab(
            in: space,
            activate: activate,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func createTransientExtensionTab(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        requireTabManager(operation: "create a transient tab").createTransientExtensionTab(
            url: url.absoluteString,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) {
        let resolvedTargetSpaceId = targetSpace?.id ?? tab.spaceId
        tabManager?.pinTab(
            tab,
            context: .init(windowState: targetWindow, spaceId: resolvedTargetSpaceId)
        )
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        tabManager?.isTransientExtensionTab(tab) ?? false
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard let tabManager, tabManager.isTransientExtensionTab(tab) else {
            return false
        }

        guard let targetSpace = tab.spaceId.flatMap({ spaceId in
            tabManager.spaces.first(where: { $0.id == spaceId })
        }) else {
            return false
        }

        return tabManager.promoteTransientExtensionTab(
            tab,
            in: targetSpace,
            activate: false
        )
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        tabManager?.isAuxiliaryMiniWindowTab(tab) ?? false
    }

    func isPinnedExtensionTab(_ tab: Tab) -> Bool {
        tab.isPinned || tabManager?.pinnedTabs.contains(where: { $0.id == tab.id }) == true
    }

    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState) {
        dependencies.selectTab(tab, windowState)
    }

    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        dependencies.materializeVisibleTabWebViewIfNeeded(tab, windowState)
    }

    func extensionWindowOwnedWebView(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView? {
        dependencies.windowOwnedWebView(tab, windowId)
    }

    func assignExtensionWebView(
        _ webView: WKWebView,
        to tab: Tab,
        in windowState: BrowserWindowState
    ) {
        dependencies.webViewCoordinator()?.setWebView(webView, for: tab.id, in: windowState.id)
    }

    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager?.session(for: tab)
    }

    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager?.session(for: sessionId)
    }

    func auxiliaryWindowSession(for window: NSWindow) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager?.session(for: window)
    }

    func focusedExtensionMiniWindowAdapter(
        forOwnerExtensionID ownerExtensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        auxiliaryWindowManager?.focusedMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        )
    }

    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID) {
        auxiliaryWindowManager?.recordAuxiliarySessionFocus(sessionId)
    }

    func focusAuxiliaryWindowSession(_ sessionId: UUID) {
        auxiliaryWindowManager?.focus(sessionID: sessionId)
    }

    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession) {
        auxiliaryWindowManager?.teardown(for: session.webView, reason: .extensionRequestedClose)
    }

    func closeAuxiliaryWindowWebView(_ webView: WKWebView) {
        auxiliaryWindowManager?.teardown(for: webView, reason: .extensionRequestedClose)
    }

    func closeAuxiliaryWindowSessions(
        forExtensionId extensionId: String,
        reason: AuxiliaryWindowCloseReason
    ) {
        auxiliaryWindowManager?.closeAll(forExtensionId: extensionId, reason: reason)
    }

    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool {
        auxiliaryWindowManager?.contains(webView: webView) ?? false
    }

    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        shouldActivateApp: Bool,
        extensionOwnedSourceURL: URL?,
        ownerExtensionID: String?
    ) -> WKWebView? {
        auxiliaryWindowManager?.presentExtensionExternalWebPopup(
            configuration: configuration,
            request: request,
            windowFeatures: windowFeatures,
            openerTab: openerTab,
            shouldActivateApp: shouldActivateApp,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            ownerExtensionID: ownerExtensionID
        )
    }

    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter? {
        await auxiliaryWindowManager?.presentExtensionPopupWindow(
            configuration: configuration,
            controller: controller,
            extensionContext: extensionContext,
            extensionManager: extensionManager,
            parentWindow: parentWindow
        )
    }

    func extensionURLHubFallbackAnchorView(for windowId: UUID) -> NSView? {
        dependencies.urlBarHubAnchorView(windowId)
    }
}

@available(macOS 15.5, *)
extension BrowserExtensionBridgeAdapter.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            auxiliaryWindowManager: { [weak browserManager] in
                browserManager?.auxiliaryWindowManager
            },
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            tabsForWebExtensionWindow: { [weak browserManager] windowState in
                guard let browserManager else { return [] }
                return browserManager.shellSelectionService.tabsForWebExtensionWindow(
                    in: windowState,
                    tabStore: browserManager.tabManager.runtimeStore
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            currentTabForActiveWindow: { [weak browserManager] in
                browserManager?.activePageRoutingOwner.currentTabForActiveWindow()
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.windowOwnedWebView(for: tab, in: windowId)
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowShellCommandOwner.createNewWindow()
            },
            urlBarHubAnchorView: { [weak browserManager] windowId in
                browserManager?.chromePopoverRoutingOwner.urlBarHubPopoverPresenter.anchorView(
                    for: windowId
                )
            }
        )
    }
}
