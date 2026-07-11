import AppKit
import Foundation
import WebKit

/// Bridges browser window/tab lifecycle into the WebKit extension runtime:
/// forwards open/close/focus/activate events to controllers, re-syncs open
/// tabs after context loads, and answers live tab/WebView queries.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserRuntimeBridgeOwner {
    struct Dependencies {
        let adapterStore: ExtensionBrowserAdapterStore
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
        let auxiliaryWindows:
            @MainActor () -> (any ExtensionAuxiliaryWindowControl)?
        let resolvedProfileIdForTab: @MainActor (Tab?) -> UUID?
        let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
        let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let extensionControllerForTab: @MainActor (Tab) -> WKWebExtensionController?
        let extensionContexts: @MainActor (UUID) -> [String: WKWebExtensionContext]
        let isTabEligibleForCurrentExtensionRuntime: @MainActor (Tab) -> Bool
        let extensionsLoaded: @MainActor () -> Bool
        let extensionLoadGeneration: @MainActor () -> UInt64
        let extensionControllerDescription: @MainActor (WKWebExtensionController?) -> String
        let currentExtensionController: @MainActor () -> WKWebExtensionController?
        let ownedUntrackedCurrentWebView: @MainActor (Tab) -> WKWebView?
        let trace: @MainActor (String) -> Void
        let debugDidFocusWindow: @MainActor () -> ((UUID) -> Void)?
        let debugDidActivateTab: @MainActor () -> ((UUID) -> Void)?
    }

    private let dependencies: Dependencies
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let runtimeReload: ExtensionRuntimeReloadTransaction

    init(
        manager: ExtensionManager,
        dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        let normalWindows = ExtensionNormalWindowLifecycle(
            resolver: ExtensionNormalWindowProjectionResolver(
                manager: manager
            ),
            adapterStore: dependencies.adapterStore
        )
        self.normalWindows = normalWindows
        runtimeReload = ExtensionRuntimeReloadTransaction(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            normalWindows: normalWindows,
            adapterResolution: manager.adapterResolutionOwner,
            controllerBinding: manager.controllerAttachmentOwner,
            tabPublication: manager.normalTabRuntimeBindingOwner,
            diagnostics: manager.runtimeDiagnostics
        )
    }

    // MARK: - Window Notifications

    @discardableResult
    func notifyWindowOpened(_ windowState: BrowserWindowState) -> Bool {
        normalWindows.opened(windowState)
    }

    func publishWindow(
        _ windowState: BrowserWindowState
    ) -> (any BrowserWindowExtensionPublication)? {
        normalWindows.publication(for: windowState)
    }

    func notifyWindowClosed(_ windowState: BrowserWindowState) {
        normalWindows.closed(windowState)
    }

    func notifyAuxiliaryWindowOpened(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            return
        }

        extensionContext.didOpenWindow(adapter)
        if session.shouldActivateApp {
            dependencies.auxiliaryWindows()?
                .recordAuxiliaryWindowSessionFocus(session.id)
            extensionContext.didFocusWindow(adapter)
        }
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            return
        }

        guard extensionContext.openWindows.contains(where: { window in
            (window as? ExtensionMiniWindowAdapter)?.sessionId == session.id
        }) else {
            return
        }
        if (extensionContext.focusedWindow as? ExtensionMiniWindowAdapter)?.sessionId == session.id {
            return
        }

        extensionContext.didFocusWindow(adapter)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            dependencies.adapterStore.removeMiniWindowAdapter(for: session.id)
            return
        }

        extensionContext.didCloseWindow(adapter)
        if let activeWindow = dependencies.windowQuery()?
            .activeExtensionWindowState,
           let profileId = dependencies.resolvedProfileIdForTab(session.tab),
           dependencies.windowMatchesProfile(activeWindow, profileId),
           let focusedAdapter = dependencies.windowAdapter(activeWindow.id) {
            extensionContext.didFocusWindow(focusedAdapter)
        } else {
            extensionContext.didFocusWindow(nil)
        }

        dependencies.adapterStore.removeMiniWindowAdapter(for: session.id)
    }

    private func auxiliaryOwnerExtensionContext(
        for session: AuxiliaryWindowSession
    ) -> WKWebExtensionContext? {
        if let context = session.tab.webExtensionContextOverride {
            return context
        }

        guard let ownerExtensionID = session.ownerExtensionID,
              let profileId = dependencies.resolvedProfileIdForTab(session.tab)
        else {
            return nil
        }

        return dependencies.extensionContexts(profileId)[ownerExtensionID]
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        if let keyWindow = NSApp.keyWindow,
           let auxiliaryWindows = dependencies.auxiliaryWindows(),
           let auxiliarySession = auxiliaryWindows.auxiliaryWindowSession(
            for: keyWindow
           ) {
            auxiliaryWindows.focusAuxiliaryWindowSession(auxiliarySession.id)
            return
        }

        normalWindows.focused(windowState)
        dependencies.debugDidFocusWindow()?(windowState.id)
    }

    /// Balances every normal-window open before contexts/controllers are torn
    /// down. Entries leave the map before callbacks so reentrant close cannot
    /// publish a duplicate event.
    @discardableResult
    func closePublishedWindowsForRuntimeTeardown()
        -> ExtensionRuntimeReloadTransaction.RetirementOutcome {
        runtimeReload.retireRuntime(dependencies.runtime())
    }

    func publishedWindowAdapter(
        for windowState: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        normalWindows.publishedAdapter(
            for: windowState,
            profileID: profileID
        )
    }

    func prepareTabOpen(_ tab: Tab) -> Bool {
        normalWindows.prepareTabOpen(tab)
    }

    // MARK: - Tab Notifications

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard normalWindows.prepareTabActivation(newTab) else {
            return
        }
        guard dependencies.isTabEligibleForCurrentExtensionRuntime(newTab) else {
            return
        }
        guard let controller = dependencies.extensionControllerForTab(newTab),
              let newAdapter = dependencies.stableAdapter(newTab) else { return }
        let newProfileID = dependencies.resolvedProfileIdForTab(newTab)
        let previousAdapter: ExtensionTabAdapter? = previous.flatMap { tab in
            guard dependencies.isTabEligibleForCurrentExtensionRuntime(tab),
                  dependencies.resolvedProfileIdForTab(tab) == newProfileID,
                  dependencies.extensionControllerForTab(tab) === controller
            else {
                return nil
            }
            return dependencies.stableAdapter(tab)
        }
        controller.didActivateTab(newAdapter, previousActiveTab: previousAdapter)
        dependencies.debugDidActivateTab()?(newTab.id)
        controller.didSelectTabs([newAdapter])
        if let previousAdapter {
            controller.didDeselectTabs([previousAdapter])
        }
    }

    func notifyTabClosed(_ tab: Tab) {
        guard let controller = dependencies.extensionControllerForTab(tab),
              let adapter = dependencies.stableAdapter(tab) else { return }
        controller.didCloseTab(adapter, windowIsClosing: false)
        dependencies.adapterStore.removeTabAdapter(for: tab.id)
    }

    // MARK: - Runtime Reconciliation

    /// - Parameter allowWhenExtensionsNotLoaded: Use during `performInstallation` so tabs re-bind
    ///   after `load(extensionContext:)` even before `loadInstalledExtensions` sets `extensionsLoaded`.
    /// Re-binds open tabs and late-assigns the extension controller after a context load
    /// so WebKit can inject content scripts on already-open normal tabs.
    func reconcileOpenTabsAfterExtensionContextLoad(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileId: UUID? = nil
    ) {
        guard let commit = runtimeReload.reload(
            ExtensionRuntimeReloadTransaction.Request(
                reason: reason,
                allowWhenExtensionsNotLoaded:
                    allowWhenExtensionsNotLoaded,
                requestedProfileID: profileId,
                extensionsLoaded: dependencies.extensionsLoaded(),
                runtime: dependencies.runtime(),
                windowQuery: dependencies.windowQuery()
            )
        ) else {
            return
        }

        if let activeWindow = commit.activeWindow,
           commit.activeTab != nil {
            notifyWindowFocused(activeWindow)
            guard let target = runtimeReload.activationTarget(
                after: commit,
                windowQuery: dependencies.windowQuery()
            ) else {
                return
            }
            notifyTabActivated(newTab: target.tab, previous: nil)
        }
    }

    func registerExistingWindowStateIfAttached() {
        guard let windowQuery = dependencies.windowQuery() else { return }

        let windows = windowQuery.allExtensionWindowStates
        dependencies.trace(
            "registerExistingWindowState start generation=\(dependencies.extensionLoadGeneration()) windows=\(windows.count) controller=\(dependencies.extensionControllerDescription(dependencies.currentExtensionController()))"
        )

        for windowState in windows {
            notifyWindowOpened(windowState)
        }

        if let activeWindow = windowQuery.activeExtensionWindowState {
            notifyWindowFocused(activeWindow)
        }

        dependencies.trace(
            "registerExistingWindowState complete generation=\(dependencies.extensionLoadGeneration()) windows=\(windows.count)"
        )
    }

    // MARK: - Runtime Queries

    func allKnownTabs() -> [Tab] {
        let runtime = dependencies.runtime()
        var tabs = runtime.allTabs()
        for windowState in runtime.allWindowStates() {
            tabs.append(contentsOf: windowState.ephemeralTabs)
        }

        return tabs
    }

    func liveWebViews(for tab: Tab) -> [WKWebView] {
        let runtime = dependencies.runtime()
        guard runtime.browserRuntimeAvailable() else { return [] }

        var webViews: [WKWebView] = []

        if let primaryWindowId = runtime.primaryTrackedWindowId(tab.id),
           let webView = runtime.windowOwnedWebView(tab, primaryWindowId) {
            webViews.append(webView)
        }
        if let webView = dependencies.ownedUntrackedCurrentWebView(tab) {
            webViews.append(webView)
        }
        webViews.append(contentsOf: runtime.trackedWebViews(tab.id))

        var uniqueWebViews: [WKWebView] = []
        var seen: Set<ObjectIdentifier> = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            guard seen.insert(identifier).inserted else { continue }
            uniqueWebViews.append(webView)
        }

        return uniqueWebViews
    }

    func pruneRuntimeAdapters() {
        let runtime = dependencies.runtime()
        let windowStates = runtime.allWindowStates()
        let liveTabIDs = Set(
            runtime.allTabs().map(\.id)
                + windowStates.flatMap(\.ephemeralTabs).map(\.id)
        )
        let liveWindowIDs = Set(windowStates.map(\.id))
        dependencies.adapterStore.prune(liveTabIDs: liveTabIDs, liveWindowIDs: liveWindowIDs)
    }
}

@available(macOS 15.5, *)
extension ExtensionBrowserRuntimeBridgeOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            adapterStore: manager.adapterStore,
            runtime: { [weak manager] in manager?.runtime ?? .inactive },
            windowQuery: { [weak manager] in manager?.extensionWindowQuery },
            auxiliaryWindows: { [weak manager] in
                manager?.extensionAuxiliaryWindows
            },
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            windowAdapter: { [weak manager] windowId in
                manager?.adapterResolutionOwner.windowAdapter(for: windowId)
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            },
            extensionControllerForTab: { [weak manager] tab in
                manager?.extensionController(for: tab)
            },
            extensionContexts: { [weak manager] profileId in
                manager?.extensionContexts(for: profileId) ?? [:]
            },
            isTabEligibleForCurrentExtensionRuntime: { [weak manager] tab in
                manager?.isTabEligibleForCurrentExtensionRuntime(tab) ?? false
            },
            extensionsLoaded: { [weak manager] in manager?.extensionsLoaded ?? false },
            extensionLoadGeneration: { [weak manager] in
                manager?.runtimeSession.extensionLoadGeneration ?? 0
            },
            extensionControllerDescription: { controller in
                ExtensionRuntimeDiagnostics.objectDescription(controller)
            },
            currentExtensionController: { [weak manager] in manager?.extensionController },
            ownedUntrackedCurrentWebView: { [weak manager] tab in
                manager?.ownedUntrackedCurrentWebView(for: tab)
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            },
            debugDidFocusWindow: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.didFocusWindow
                #else
                    nil
                #endif
            },
            debugDidActivateTab: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.didActivateTab
                #else
                    nil
                #endif
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func notifyWindowOpened(_ windowState: BrowserWindowState) -> Bool {
        browserRuntimeBridgeOwner.notifyWindowOpened(windowState)
    }

    func notifyWindowClosed(_ windowState: BrowserWindowState) {
        browserRuntimeBridgeOwner.notifyWindowClosed(windowState)
    }

    func notifyAuxiliaryWindowOpened(_ session: AuxiliaryWindowSession) {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowOpened(session)
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowFocused(session)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        browserRuntimeBridgeOwner.notifyAuxiliaryWindowClosed(session)
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        browserRuntimeBridgeOwner.notifyWindowFocused(windowState)
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        browserRuntimeBridgeOwner.notifyTabActivated(newTab: newTab, previous: previous)
    }

    func notifyTabClosed(_ tab: Tab) {
        browserRuntimeBridgeOwner.notifyTabClosed(tab)
    }

    func reconcileOpenTabsAfterExtensionContextLoad(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileId: UUID? = nil
    ) {
        browserRuntimeBridgeOwner.reconcileOpenTabsAfterExtensionContextLoad(
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded,
            profileId: profileId
        )
    }

    func registerExistingWindowStateIfAttached() {
        browserRuntimeBridgeOwner.registerExistingWindowStateIfAttached()
    }

    func allKnownTabs() -> [Tab] {
        browserRuntimeBridgeOwner.allKnownTabs()
    }

    func liveWebViews(for tab: Tab) -> [WKWebView] {
        browserRuntimeBridgeOwner.liveWebViews(for: tab)
    }

    func pruneRuntimeAdapters() {
        browserRuntimeBridgeOwner.pruneRuntimeAdapters()
    }
}
