import AppKit
import Foundation
import WebKit

/// Adapts browser windows, tabs, and auxiliary windows to the WebExtension
/// bridge protocol. Replaces the former god-object conformance of
/// `BrowserManager` to `ExtensionBrowserBridgeContext`.
@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionBridgeAdapter {
    private let windowRegistryProvider: @MainActor () -> WindowRegistry?
    private let tabManagerProvider: @MainActor () -> TabManager?
    private let auxiliaryWindowManagerProvider: @MainActor () -> AuxiliaryWindowManager?
    private let webViewCoordinator: @MainActor () -> WebViewCoordinator?
    private let tabsForWebExtensionWindow: @MainActor (BrowserWindowState) -> [Tab]
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let currentTabForActiveWindow: @MainActor () -> Tab?
    private let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    private let materializeVisibleTabWebViewIfNeeded: @MainActor (Tab, BrowserWindowState) -> Void
    private let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
    private let assignWebView: @MainActor (WKWebView, Tab, UUID) -> Void
    private let installUntrackedOwnedWebView: @MainActor (WKWebView, Tab) -> Void
    private let replaceLiveWebView: @MainActor (
        Tab,
        UUID?,
        String,
        ((WKWebViewConfiguration) -> Void)?,
        ((WKWebView) -> Void)?,
        ((WKWebView) -> Bool)?
    ) -> WKWebView?
    private let createNewWindow: @MainActor () -> Void
    private let urlBarHubAnchorView: @MainActor (UUID) -> NSView?
    private let sumiSettings: @MainActor () -> SumiSettingsService?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        tabManager: @escaping @MainActor () -> TabManager?,
        auxiliaryWindowManager: @escaping @MainActor () -> AuxiliaryWindowManager?,
        webViewCoordinator: @escaping @MainActor () -> WebViewCoordinator?,
        tabsForWebExtensionWindow: @escaping @MainActor (BrowserWindowState) -> [Tab],
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        currentTabForActiveWindow: @escaping @MainActor () -> Tab?,
        windowStateContainingTab: @escaping @MainActor (Tab) -> BrowserWindowState?,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        materializeVisibleTabWebViewIfNeeded: @escaping @MainActor (Tab, BrowserWindowState) -> Void,
        windowOwnedWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?,
        assignWebView: @escaping @MainActor (WKWebView, Tab, UUID) -> Void,
        installUntrackedOwnedWebView: @escaping @MainActor (WKWebView, Tab) -> Void,
        replaceLiveWebView: @escaping @MainActor (
            Tab,
            UUID?,
            String,
            ((WKWebViewConfiguration) -> Void)?,
            ((WKWebView) -> Void)?,
            ((WKWebView) -> Bool)?
        ) -> WKWebView?,
        createNewWindow: @escaping @MainActor () -> Void,
        urlBarHubAnchorView: @escaping @MainActor (UUID) -> NSView?,
        sumiSettings: @escaping @MainActor () -> SumiSettingsService?
    ) {
        self.windowRegistryProvider = windowRegistry
        self.tabManagerProvider = tabManager
        self.auxiliaryWindowManagerProvider = auxiliaryWindowManager
        self.webViewCoordinator = webViewCoordinator
        self.tabsForWebExtensionWindow = tabsForWebExtensionWindow
        self.currentTab = currentTab
        self.currentTabForActiveWindow = currentTabForActiveWindow
        self.windowStateContainingTab = windowStateContainingTab
        self.selectTab = selectTab
        self.materializeVisibleTabWebViewIfNeeded = materializeVisibleTabWebViewIfNeeded
        self.windowOwnedWebView = windowOwnedWebView
        self.assignWebView = assignWebView
        self.installUntrackedOwnedWebView = installUntrackedOwnedWebView
        self.replaceLiveWebView = replaceLiveWebView
        self.createNewWindow = createNewWindow
        self.urlBarHubAnchorView = urlBarHubAnchorView
        self.sumiSettings = sumiSettings
    }

    private var windowRegistry: WindowRegistry? {
        windowRegistryProvider()
    }

    private var tabManager: TabManager? {
        tabManagerProvider()
    }

    private var auxiliaryWindowManager: AuxiliaryWindowManager? {
        auxiliaryWindowManagerProvider()
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
        if let tab = tabManager?.tabCollectionMembershipOwner.tab(for: tabId) {
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
        windowStateContainingTab(tab)
    }

    func extensionWindowState(forAppKitWindow window: NSWindow) -> BrowserWindowState? {
        windowRegistry?.windowState(containing: window)
    }

    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windowRegistry?.appKitWindow(for: windowState)
    }

    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab? {
        currentTab(windowState)
    }

    func currentExtensionTabForActiveWindow() -> Tab? {
        currentTabForActiveWindow()
    }

    func currentExtensionTabForPopup() -> Tab? {
        currentTabForActiveWindow()
    }

    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab] {
        tabsForWebExtensionWindow(windowState)
    }

    func extensionSpace(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager?.spaceStateOwner.space(with: spaceId)
    }

    func extensionTargetSpace(for windowState: BrowserWindowState?) -> Space? {
        guard let windowState else { return nil }

        if let currentSpaceId = windowState.currentSpaceId,
           let currentSpace = extensionSpace(for: currentSpaceId),
           windowState.currentProfileId.map({ currentSpace.profileId == $0 }) ?? true {
            return currentSpace
        }

        if let profileId = windowState.currentProfileId,
           let profileSpace = tabManager?.spaceStateOwner.firstSpace(forProfile: profileId) {
            return profileSpace
        }

        return nil
    }

    func extensionTargetSpace(for tab: Tab) -> Space? {
        tab.spaceId.flatMap(extensionSpace(for:))
    }

    func extensionTargetSpace(matchingProfile profileId: UUID) -> Space? {
        tabManager?.spaceStateOwner.firstSpace(forProfile: profileId)
    }

    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        if let primaryWindowId = webViewCoordinator()?.primaryTrackedWindowId(for: tab.id),
           let primaryWindow = windowRegistry?.windows[primaryWindowId] {
            return primaryWindow
        }

        if let containing = windowStateContainingTab(tab) {
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
        createNewWindow()
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
            return tabManager.regularTabLifecycleOwner.createNewTab(
                url: url.absoluteString,
                in: space,
                activate: activate,
                webExtensionContextOverride: webExtensionContextOverride
            )
        }

        return tabManager.regularTabLifecycleOwner.createNewTab(
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
        requireTabManager(operation: "create a transient tab").transientWebKitTabLifecycleOwner.createTransientExtensionTab(
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
        tabManager?.shortcutPinCommandOwner.pinTab(
            tab,
            context: .init(windowState: targetWindow, spaceId: resolvedTargetSpaceId)
        )
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        tabManager?.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab) ?? false
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard let tabManager, tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab) else {
            return false
        }

        guard let targetSpace = tab.spaceId.flatMap({ spaceId in
            tabManager.spaceStateOwner.spaces.first(where: { $0.id == spaceId })
        }) else {
            return false
        }

        return tabManager.transientWebKitTabLifecycleOwner.promoteTransientExtensionTab(
            tab,
            in: targetSpace,
            activate: false
        )
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        tabManager?.transientWebKitTabLifecycleOwner.isAuxiliaryMiniWindowTab(tab) ?? false
    }

    func isPinnedExtensionTab(_ tab: Tab) -> Bool {
        tab.isPinned || tabManager?.shortcutPresentationOwner.activeShortcutTabs().contains(where: { $0.id == tab.id }) == true
    }

    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState) {
        selectTab(tab, windowState)
    }

    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        materializeVisibleTabWebViewIfNeeded(tab, windowState)
    }

    func extensionWindowOwnedWebView(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView? {
        windowOwnedWebView(tab, windowId)
    }

    func assignExtensionWebView(
        _ webView: WKWebView,
        to tab: Tab,
        in windowState: BrowserWindowState
    ) {
        assignWebView(webView, tab, windowState.id)
    }

    func replaceUntrackedExtensionWebView(
        _ webView: WKWebView,
        for tab: Tab
    ) {
        installUntrackedOwnedWebView(webView, tab)
    }

    func replaceExtensionLiveWebView(
        for tab: Tab,
        in windowState: BrowserWindowState?,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)?,
        prepareReplacement: ((WKWebView) -> Void)?,
        validate: ((WKWebView) -> Bool)?
    ) -> WKWebView? {
        replaceLiveWebView(
            tab,
            windowState?.id,
            reason,
            prepareConfiguration,
            prepareReplacement,
            validate
        )
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
        urlBarHubAnchorView(windowId)
    }

    func extensionActionPopupAppearance(
        forAnchorWindow window: NSWindow,
        fallback: NSAppearance?
    ) -> NSAppearance? {
        guard let settings = sumiSettings(),
              let windowState = extensionWindowState(forAppKitWindow: window)
        else {
            return nil
        }
        return windowState.nativeSurfaceAppearance(
            settings: settings,
            fallback: fallback,
            in: windowRegistry
        )
    }
}
