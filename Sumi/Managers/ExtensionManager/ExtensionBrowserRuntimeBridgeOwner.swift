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
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let controllersByProfile: @MainActor () -> [UUID: WKWebExtensionController]
        let currentProfileId: @MainActor () -> UUID?
        let resolvedProfileIdForWindow: @MainActor (BrowserWindowState) -> UUID?
        let resolvedProfileIdForTab: @MainActor (Tab?) -> UUID?
        let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
        let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
        let stableAdapter: @MainActor (Tab) -> ExtensionTabAdapter?
        let extensionControllerForTab: @MainActor (Tab) -> WKWebExtensionController?
        let extensionContexts: @MainActor (UUID) -> [String: WKWebExtensionContext]
        let isTabEligibleForCurrentExtensionRuntime: @MainActor (Tab) -> Bool
        let switchProfile: @MainActor (UUID) -> Void
        let extensionsLoaded: @MainActor () -> Bool
        let tabOpenNotificationGeneration: @MainActor () -> UInt64
        let bumpTabOpenNotificationGeneration: @MainActor () -> UInt64
        let updateWebViewsForProfile: @MainActor (UUID, Bool) -> Void
        let registerTabWithExtensionRuntime: @MainActor (Tab, String, Bool) -> Void
        let notifyTabActivated: @MainActor (Tab, Tab?) -> Void
        let extensionLoadGeneration: @MainActor () -> UInt64
        let extensionControllerDescription: @MainActor (WKWebExtensionController?) -> String
        let currentExtensionController: @MainActor () -> WKWebExtensionController?
        let ownedUntrackedCurrentWebView: @MainActor (Tab) -> WKWebView?
        let trace: @MainActor (String) -> Void
        let debugDidActivateTab: @MainActor () -> ((UUID) -> Void)?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Window Notifications

    func notifyWindowOpened(_ windowState: BrowserWindowState) {
        guard let profileId = dependencies.resolvedProfileIdForWindow(windowState),
              let controller = dependencies.controllersByProfile()[profileId],
              let adapter = dependencies.windowAdapter(windowState.id) else {
            return
        }
        controller.didOpenWindow(adapter)
    }

    func notifyWindowClosed(_ windowId: UUID) {
        dependencies.adapterStore.removeWindowAdapter(for: windowId)
    }

    func notifyAuxiliaryWindowOpened(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            return
        }

        extensionContext.didOpenWindow(adapter)
        if session.shouldActivateApp {
            dependencies.browserBridgeContext()?.recordAuxiliaryWindowSessionFocus(session.id)
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
        if let activeWindow = dependencies.browserBridgeContext()?.activeExtensionWindowState,
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
           let auxiliarySession = dependencies.browserBridgeContext()?
           .auxiliaryWindowSession(for: keyWindow) {
            dependencies.browserBridgeContext()?.focusAuxiliaryWindowSession(auxiliarySession.id)
            return
        }

        let runtime = dependencies.runtime()
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            dependencies.switchProfile(profile.id)
        } else if let profileId = windowState.currentProfileId,
                  runtime.profile(profileId) != nil {
            dependencies.switchProfile(profileId)
        } else if let currentProfile = runtime.currentProfile() {
            dependencies.switchProfile(currentProfile.id)
        }

        guard let profileId = dependencies.resolvedProfileIdForWindow(windowState),
              let controller = dependencies.controllersByProfile()[profileId],
              let adapter = dependencies.windowAdapter(windowState.id) else {
            return
        }
        controller.didFocusWindow(adapter)
    }

    // MARK: - Tab Notifications

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard dependencies.isTabEligibleForCurrentExtensionRuntime(newTab) else {
            return
        }
        guard let controller = dependencies.extensionControllerForTab(newTab),
              let newAdapter = dependencies.stableAdapter(newTab) else { return }
        let previousAdapter = previous.flatMap { tab in
            dependencies.isTabEligibleForCurrentExtensionRuntime(tab)
                ? dependencies.stableAdapter(tab)
                : nil
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

    /// Call immediately after `tabOpenNotificationGeneration` is incremented so WebKit never
    /// observes a window whose `tabs(for:)` can list adapters while `activeTab(for:)` is `nil`
    /// only because tabs have not yet been reconciled to the new generation.
    ///
    /// - Parameter allowWhenExtensionsNotLoaded: Use during `performInstallation` so tabs re-bind
    ///   after `load(extensionContext:)` even before `loadInstalledExtensions` sets `extensionsLoaded`.
    /// Re-binds open tabs and late-assigns the extension controller after a context load
    /// so WebKit can inject content scripts on already-open normal tabs.
    func reconcileOpenTabsAfterExtensionContextLoad(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileId: UUID? = nil
    ) {
        _ = dependencies.bumpTabOpenNotificationGeneration()
        var profileIds = Set(dependencies.controllersByProfile().keys)
        if let profileId {
            profileIds.insert(profileId)
        }
        if let currentProfileId = dependencies.currentProfileId() {
            profileIds.insert(currentProfileId)
        }
        // Attach or rebuild WebViews before `didOpenTab` so WebKit can inject manifest
        // content scripts (including CSS) on already-open normal tabs.
        for resolvedProfileId in profileIds {
            dependencies.updateWebViewsForProfile(
                resolvedProfileId,
                allowWhenExtensionsNotLoaded
            )
        }
        resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
        registerExistingWindowStateIfAttached()
    }

    func resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard dependencies.extensionsLoaded() || allowWhenExtensionsNotLoaded else { return }

        let tabs = allKnownTabs()
        dependencies.trace(
            "resyncOpenTabsAfterGenerationBump start reason=\(reason) generation=\(dependencies.tabOpenNotificationGeneration()) tabs=\(tabs.count) allowWhenNotLoaded=\(allowWhenExtensionsNotLoaded)"
        )

        for tab in tabs {
            dependencies.registerTabWithExtensionRuntime(
                tab,
                reason,
                allowWhenExtensionsNotLoaded
            )
        }

        if let browserContext = dependencies.browserBridgeContext(),
           let activeWindow = browserContext.activeExtensionWindowState,
           let currentTab = browserContext.currentExtensionTab(in: activeWindow),
           dependencies.isTabEligibleForCurrentExtensionRuntime(currentTab) {
            dependencies.notifyTabActivated(currentTab, nil)
        }

        dependencies.trace(
            "resyncOpenTabsAfterGenerationBump complete reason=\(reason) generation=\(dependencies.tabOpenNotificationGeneration())"
        )
    }

    func registerExistingWindowStateIfAttached() {
        guard let browserContext = dependencies.browserBridgeContext() else { return }

        let windows = browserContext.allExtensionWindowStates
        dependencies.trace(
            "registerExistingWindowState start generation=\(dependencies.extensionLoadGeneration()) notifyGeneration=\(dependencies.tabOpenNotificationGeneration()) windows=\(windows.count) controller=\(dependencies.extensionControllerDescription(dependencies.currentExtensionController()))"
        )

        for windowState in windows {
            notifyWindowOpened(windowState)
        }

        if let activeWindow = browserContext.activeExtensionWindowState {
            notifyWindowFocused(activeWindow)
        }

        dependencies.trace(
            "registerExistingWindowState complete generation=\(dependencies.extensionLoadGeneration()) notifyGeneration=\(dependencies.tabOpenNotificationGeneration()) windows=\(windows.count)"
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
            browserBridgeContext: { [weak manager] in manager?.browserBridgeContext },
            controllersByProfile: { [weak manager] in
                manager?.extensionControllersByProfile ?? [:]
            },
            currentProfileId: { [weak manager] in manager?.currentProfileId },
            resolvedProfileIdForWindow: { [weak manager] windowState in
                manager?.resolvedProfileId(for: windowState)
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
            switchProfile: { [weak manager] profileId in
                manager?.switchProfile(profileId: profileId)
            },
            extensionsLoaded: { [weak manager] in manager?.extensionsLoaded ?? false },
            tabOpenNotificationGeneration: { [weak manager] in
                manager?.tabOpenNotificationGeneration ?? 0
            },
            bumpTabOpenNotificationGeneration: { [weak manager] in
                guard let manager else { return 0 }
                manager.tabOpenNotificationGeneration &+= 1
                return manager.tabOpenNotificationGeneration
            },
            updateWebViewsForProfile: { [weak manager] profileId, allowWhenExtensionsNotLoaded in
                manager?.updateWebViewsForProfile(
                    profileId,
                    allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
                )
            },
            registerTabWithExtensionRuntime: { [weak manager] tab, reason, allowWhenExtensionsNotLoaded in
                manager?.registerTabWithExtensionRuntime(
                    tab,
                    reason: reason,
                    allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
                )
            },
            notifyTabActivated: { [weak manager] newTab, previous in
                manager?.notifyTabActivated(newTab: newTab, previous: previous)
            },
            extensionLoadGeneration: { [weak manager] in
                manager?.extensionLoadGeneration ?? 0
            },
            extensionControllerDescription: { [weak manager] controller in
                manager?.extensionRuntimeControllerDescription(controller) ?? "nil"
            },
            currentExtensionController: { [weak manager] in manager?.extensionController },
            ownedUntrackedCurrentWebView: { [weak manager] tab in
                manager?.ownedUntrackedCurrentWebView(for: tab)
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
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
    func notifyWindowOpened(_ windowState: BrowserWindowState) {
        browserRuntimeBridgeOwner.notifyWindowOpened(windowState)
    }

    func notifyWindowClosed(_ windowId: UUID) {
        browserRuntimeBridgeOwner.notifyWindowClosed(windowId)
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

    func resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        browserRuntimeBridgeOwner.resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
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
