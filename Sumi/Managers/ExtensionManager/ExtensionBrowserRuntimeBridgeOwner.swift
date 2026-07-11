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
        let extensionsLoaded: @MainActor () -> Bool
        let extensionLoadGeneration: @MainActor () -> UInt64
        let extensionControllerDescription: @MainActor (WKWebExtensionController?) -> String
        let currentExtensionController: @MainActor () -> WKWebExtensionController?
        let ownedUntrackedCurrentWebView: @MainActor (Tab) -> WKWebView?
        let trace: @MainActor (String) -> Void
        let debugDidFocusWindow: @MainActor () -> ((UUID) -> Void)?
    }

    private let dependencies: Dependencies
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let auxiliaryWindowLifecycle: ExtensionAuxiliaryWindowLifecycle
    let windowPublications: ExtensionWindowPublicationQuery
    let tabPublicationAdmission: ExtensionTabPublicationAdmission
    private let tabActivation: ExtensionNormalTabActivationTransaction
    private let tabClose: ExtensionNormalTabCloseTransaction
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
        let auxiliaryTabPublication = ExtensionAuxiliaryTabPublicationPreparer(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            adapterStore: dependencies.adapterStore,
            controllerBinding: manager.controllerAttachmentOwner,
            adapterResolution: manager.adapterResolutionOwner,
            extensionsLoaded: { [weak manager] in
                manager?.extensionsLoaded == true
            }
        )
        #if DEBUG
            let auxiliaryWindowLifecycle = ExtensionAuxiliaryWindowLifecycle(
                adapterStore: dependencies.adapterStore,
                profileRuntime: manager.profileRuntime,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normalWindows,
                debugEvent: { [weak manager] event in
                    manager?.dispatchAuxiliaryPublicationDebugEvent(event)
                }
            )
        #else
            let auxiliaryWindowLifecycle = ExtensionAuxiliaryWindowLifecycle(
                adapterStore: dependencies.adapterStore,
                profileRuntime: manager.profileRuntime,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normalWindows
            )
        #endif
        self.auxiliaryWindowLifecycle = auxiliaryWindowLifecycle
        let windowPublications = ExtensionWindowPublicationQuery(
            normalWindows: normalWindows,
            auxiliaryWindows: auxiliaryWindowLifecycle.publications,
            runtime: dependencies.runtime,
            control: dependencies.auxiliaryWindows
        )
        self.windowPublications = windowPublications
        tabPublicationAdmission = ExtensionTabPublicationAdmission(
            normalWindows: normalWindows,
            publications: windowPublications
        )
        let tabActivationValidator = ExtensionNormalTabActivationValidator(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            adapterStore: dependencies.adapterStore,
            adapterResolution: manager.adapterResolutionOwner,
            normalWindows: normalWindows,
            windowPublications: windowPublications,
            runtime: dependencies.runtime,
            windowQuery: dependencies.windowQuery,
            extensionsLoaded: dependencies.extensionsLoaded
        )
        #if DEBUG
            tabActivation = ExtensionNormalTabActivationTransaction(
                validator: tabActivationValidator,
                debugEvent: { [weak manager] event in
                    manager?.dispatchNormalTabLifecycleDebugEvent(event)
                }
            )
        #else
            tabActivation = ExtensionNormalTabActivationTransaction(
                validator: tabActivationValidator
            )
        #endif
        tabClose = ExtensionNormalTabCloseTransaction(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            adapterStore: dependencies.adapterStore,
            adapterResolution: manager.adapterResolutionOwner,
            windowPublications: windowPublications,
            events: manager.normalTabRuntimeBindingOwner,
            runtime: dependencies.runtime,
            extensionsLoaded: dependencies.extensionsLoaded
        )
        runtimeReload = ExtensionRuntimeReloadTransaction(
            runtimeSession: manager.runtimeSession,
            profileRuntime: manager.profileRuntime,
            normalWindows: normalWindows,
            adapterResolution: manager.adapterResolutionOwner,
            controllerBinding: manager.controllerAttachmentOwner,
            tabPublication: manager.normalTabRuntimeBindingOwner,
            isAuxiliarySessionTab: windowPublications.isAuxiliarySessionTab,
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

    @discardableResult
    func notifyAuxiliaryWindowOpened(
        _ session: AuxiliaryWindowSession
    ) -> Bool {
        auxiliaryWindowLifecycle.opened(
            session,
            runtime: dependencies.runtime(),
            control: dependencies.auxiliaryWindows()
        )
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        auxiliaryWindowLifecycle.focused(
            session,
            runtime: dependencies.runtime(),
            control: dependencies.auxiliaryWindows()
        )
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        auxiliaryWindowLifecycle.closed(
            session,
            runtime: dependencies.runtime(),
            windowQuery: dependencies.windowQuery()
        )
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
        let runtime = dependencies.runtime()
        auxiliaryWindowLifecycle.closeAllForRuntimeTeardown(
            runtime: runtime,
            control: dependencies.auxiliaryWindows()
        )
        return runtimeReload.retireRuntime(runtime)
    }

    func publishedWindowAdapter(
        for windowState: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        windowPublications.publishedWindowAdapter(
            for: windowState,
            profileID: profileID
        )
    }

    func prepareTabOpen(_ tab: Tab) -> Bool {
        tabPublicationAdmission.prepareTabOpen(tab)
    }

    // MARK: - Tab Notifications

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        tabActivation.activate(newTab, previous: previous)
    }

    func notifyTabClosed(_ tab: Tab) {
        tabClose.close(tab)
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
        let extensionsLoaded = dependencies.extensionsLoaded()
        guard extensionsLoaded || allowWhenExtensionsNotLoaded else {
            return
        }
        let runtime = dependencies.runtime()
        let control = dependencies.auxiliaryWindows()
        let suspendedAuxiliarySessions = auxiliaryWindowLifecycle
            .suspendForRuntimeReload(runtime: runtime, control: control)
        let commit = runtimeReload.reload(
            ExtensionRuntimeReloadTransaction.Request(
                reason: reason,
                allowWhenExtensionsNotLoaded:
                    allowWhenExtensionsNotLoaded,
                requestedProfileID: profileId,
                extensionsLoaded: extensionsLoaded,
                runtime: runtime,
                windowQuery: dependencies.windowQuery()
            )
        )
        auxiliaryWindowLifecycle.republishAfterRuntimeReload(
            suspendedAuxiliarySessions,
            runtime: runtime,
            control: control
        )
        guard let commit else { return }

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
        let liveTabs = runtime.allTabs()
            + windowStates.flatMap(\.ephemeralTabs)
        let liveWindowIDs = Set(windowStates.map(\.id))
        dependencies.adapterStore.prune(
            liveTabs: liveTabs,
            liveWindowIDs: liveWindowIDs
        )
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
            }
        )
    }
}
