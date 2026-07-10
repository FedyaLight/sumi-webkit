import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi
import SumiDomain


@MainActor
final class SumiNavigationPopupResponderTests: SumiNavigationResponderTestCase {
    func testGlanceTriggerRequiresCleanOptionModifier() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://source.example")!)
        tab.sumiSettings = settings

        XCTAssertTrue(tab.isGlanceTriggerActive([.option]))
        XCTAssertFalse(tab.isGlanceTriggerActive([]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.command]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.option, .command]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.control]))
        XCTAssertFalse(tab.isGlanceTriggerActive([.shift]))

        settings.glanceEnabled = false
        XCTAssertFalse(tab.isGlanceTriggerActive([.option]))
    }

    func testDynamicGlanceRequiresEssentialExternalCleanClick() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.sumiSettings = settings
        let externalURL = URL(string: "https://destination.example/page")!
        let sameHostURL = URL(string: "https://source.example/other")!

        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))

        tab.shortcutPinRole = .spacePinned
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))

        tab.shortcutPinRole = .essential
        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: sameHostURL, modifierFlags: []))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.command]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option, .command]))

        settings.glanceEnabled = false
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
    }

    func testGlanceClickUsesEventModifierFlagsInsteadOfStaleClickState() throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        let targetURL = URL(string: "https://destination.example/page")!

        tab.setClickModifierFlags([.command])
        if tab.isGlanceTriggerActive([.command]) {
            tab.openURLInGlance(targetURL)
        }
        XCTAssertNil(browserManager.glanceManager.currentSession)

        if tab.isGlanceTriggerActive([.option]) {
            tab.openURLInGlance(targetURL)
        }
        XCTAssertEqual(browserManager.glanceManager.currentSession?.currentURL, targetURL)
    }

    func testFreshNativeMouseDownWinsOverStaleWebKitModifierFlags() {
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.setClickModifierFlags([.command])
        tab.recordWebViewInteraction(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option])
        )

        XCTAssertEqual(
            tab.resolvedNavigationModifierFlags(actionFlags: [.command, .option]),
            [.option]
        )
    }

    /// Mirrors post-`createWebView` / `decidePolicy` cleanup so Cmd+click does not leave stale `lastWebViewInteractionEvent`.
    func testClearingModifierSnapshotAfterCmdGestureAllowsFreshGlanceResolution() {
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.recordWebViewInteraction(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command])
        )

        XCTAssertEqual(
            tab.resolvedNavigationModifierFlags(actionFlags: []),
            [.command]
        )

        tab.clearWebViewInteractionEvent()
        tab.setClickModifierFlags([])

        XCTAssertEqual(tab.resolvedNavigationModifierFlags(actionFlags: []), [])

        tab.recordWebViewInteraction(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.option])
        )
        let resolved = tab.resolvedNavigationModifierFlags(actionFlags: [])
        XCTAssertEqual(resolved, [.option])
        XCTAssertTrue(tab.isGlanceTriggerActive(resolved))
    }

    func testNativeContextMenuProbeConsumesChildWebViewRequestBeforeDynamicGlance() throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        tab.shortcutPinRole = .essential
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let sourceWebView = WKWebView(frame: .zero)
        let destinationURL = URL(string: "https://destination.example/image.png")!
        let navigationAction = SumiWKNavigationActionMock(
            sourceFrame: nil,
            targetFrame: nil,
            navigationType: .other,
            request: URLRequest(url: destinationURL)
        ).navigationAction
        let probe = SumiNativeContextMenuProbe()
        var childWebView: WKWebView?
        var capturedURL: URL?
        probe.onAction = {
            childWebView = responder.createWebView(
                from: sourceWebView,
                with: WKWebViewConfiguration(),
                for: navigationAction,
                windowFeatures: WKWindowFeatures()
            )
        }
        let item = NSMenuItem(
            title: "Open Image in New Window",
            action: #selector(SumiNativeContextMenuProbe.performAction(_:)),
            keyEquivalent: ""
        )
        item.target = probe

        let didConsume = responder.consumeNativeContextMenuRequest(from: item) { action in
            capturedURL = action.request.url
        }

        XCTAssertTrue(didConsume)
        XCTAssertEqual(capturedURL, destinationURL)
        XCTAssertNil(childWebView)
        XCTAssertNil(browserManager.glanceManager.currentSession)
    }

    func testPopupResponderOptionClickRoutesToGlance() async throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        tab.setClickModifierFlags([.option])
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true,
                sourceURL: tab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(browserManager.glanceManager.currentSession?.currentURL, targetURL)
    }

    func testPopupResponderEssentialExternalCleanClickRoutesToGlance() async throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        tab.shortcutPinRole = .essential
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                sourceURL: tab.url
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(browserManager.glanceManager.currentSession?.currentURL, targetURL)
    }

    func testPopupResponderRegularExternalCleanClickDoesNotRouteToGlance() async throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                sourceURL: tab.url
            ),
            preferences: &preferences
        )

        XCTAssertNil(browserManager.glanceManager.currentSession)
    }

    func testPopupResponderCommandClickDoesNotRouteToGlance() async throws {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager()
        browserManager.sumiSettings = settings
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://source.example/page")!
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.sumiSettings = settings
        tab.setClickModifierFlags([.command])
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                sourceURL: tab.url
            ),
            preferences: &preferences
        )

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [.command],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: true
            ),
            .newTab(selected: false)
        )
    }

    func testPopupResponderUsesInjectedRuntimeWithoutBrowserManager() async {
        let profile = Profile(name: "Popup Runtime")
        let tab = Tab(url: URL(string: "https://source.example/page")!, loadsCachedFaviconOnInit: false)
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profileId in
                profileId == profile.id ? profile : nil
            },
            spaceProfile: { _ in nil },
            currentProfile: { nil },
            firstProfile: { nil }
        )
        var evaluatedRequests: [SumiPopupPermissionRequest] = []
        var evaluatedContexts: [SumiPopupPermissionTabContext] = []
        tab.navigationRuntime.popupHandlingRuntime = TabPopupHandlingRuntime(
            hasBrowserRuntime: { true },
            consumeRecentlyOpenedExtensionTabRequest: { _ in false },
            evaluatePopupPermission: { request, context in
                evaluatedRequests.append(request)
                evaluatedContexts.append(context)
                return SumiPopupPermissionResult(action: .allow)
            },
            evaluatePopupPermissionForWebKitFallback: { _, _ in nil },
            openExtensionExternalTab: { _, _ in false },
            presentWebPopup: { _, _, _, _, _ in nil },
            applyVisitedLinksToPopupConfiguration: { _, _ in /* No-op. */ },
            createPopupTab: { _, _ in nil },
            installUntrackedOwnedWebView: { _, _ in /* No-op. */ },
            windowStateContainingTab: { _ in nil },
            selectTab: { _, _ in /* No-op. */ },
            notifications: { nil }
        )
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = WKWebView(frame: .zero)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: tab.url,
                modifierFlags: [.command]
            ),
            preferences: &preferences
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(evaluatedRequests.map(\.targetURL), [targetURL])
        XCTAssertEqual(evaluatedContexts.map(\.tabId), [tab.id.uuidString.lowercased()])
        XCTAssertEqual(evaluatedContexts.map(\.profilePartitionId), [profile.id.uuidString.lowercased()])
    }

    func testPopupCreateWebViewFocusesCleanClickNewTab() throws {
        let harness = try makePopupFocusHarness()
        let responder = SumiPopupHandlingNavigationResponder(tab: harness.sourceTab)
        let configuration = WKWebViewConfiguration()
        let markerScript = WKUserScript(
            source: "window.__sumiPopupConfigurationMarker = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(markerScript)
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: URL(string: "https://destination.example/page")!,
            webView: harness.sourceWebView
        )

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: configuration,
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(
            childWebView?.configuration.userContentController.userScripts.map(\.source),
            [markerScript.source]
        )
        XCTAssertNotEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(
            harness.windowState.currentTabId,
            harness.browserManager.tabManager.regularTabCollectionStateOwner.allTabsSnapshot().last?.id
        )
        let childTab = harness.browserManager.tabManager.regularTabCollectionStateOwner.allTabsSnapshot().last
        XCTAssertIdentical(childTab?.resolvedCurrentWebView(), childWebView)
        XCTAssertNil(childTab?.webViewConfigurationOverride)
    }

    func testExtensionPopupExternalCreateWebViewOpensNormalBrowserTab() async throws {
        let harness = try makePopupFocusHarness()
        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL
        let initialRegularTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
            harness.browserManager.tabManager.spaceStateOwner.currentSpace!.id
        ]?.count ?? 0

        let responder = SumiPopupHandlingNavigationResponder(tab: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: extensionPopupURL,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertTrue(harness.browserManager.tabManager.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
                harness.browserManager.tabManager.spaceStateOwner.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        let openedTab = try XCTUnwrap(harness.browserManager.tabManager.regularTabCollectionStateOwner.allTabsSnapshot().last)
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertFalse(openedTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertNil(openedTab.webViewConfigurationOverride)
        XCTAssertEqual(harness.windowState.currentTabId, openedTab.id)
        XCTAssertNotNil(openedTab.resolvedAssignedWebView() ?? openedTab.resolvedCurrentWebView())
    }

    func testExtensionPopupExternalCreateWebViewUsesOpenerWindowSpaceWhenSourceSpaceIsMissing()
        async throws {
        let harness = try makePopupFocusHarness()
        let secondarySpace = Space(
            name: "Secondary",
            profileId: harness.sourceSpace.profileId
        )
        harness.browserManager.tabManager.spaceStateOwner.append(secondarySpace)
        harness.browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)
        harness.sourceTab.spaceId = nil

        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL
        let initialWindowSpaceTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
            harness.sourceSpace.id
        ]?.count ?? 0
        let initialGlobalSpaceTabCount = harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[
            secondarySpace.id
        ]?.count ?? 0

        let responder = SumiPopupHandlingNavigationResponder(tab: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: extensionPopupURL,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[harness.sourceSpace.id]?.count,
            initialWindowSpaceTabCount + 1
        )
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[secondarySpace.id]?.count ?? 0,
            initialGlobalSpaceTabCount
        )
        let openedTab = try XCTUnwrap(harness.browserManager.tabManager.regularTabCollectionStateOwner.allTabsSnapshot().last)
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertEqual(openedTab.spaceId, harness.sourceSpace.id)
        XCTAssertEqual(harness.windowState.currentTabId, openedTab.id)
    }

    func testExtensionPopupExternalCreateWebViewUsesTabURLWhenSourceFrameMissing()
        async throws {
        let harness = try makePopupFocusHarness()
        let extensionPopupURL = URL(
            string: "safari-web-extension://extension-id/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        harness.sourceTab.url = extensionPopupURL

        let responder = SumiPopupHandlingNavigationResponder(tab: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: nil,
            targetURL: targetURL,
            webView: harness.sourceWebView
        )

        let childWebView = await responder.createWebViewAsync(
            from: harness.sourceWebView,
            with: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertTrue(harness.browserManager.tabManager.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID.isEmpty)
        let openedTab = try XCTUnwrap(harness.browserManager.tabManager.regularTabCollectionStateOwner.allTabsSnapshot().last)
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertFalse(openedTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertNil(openedTab.webViewConfigurationOverride)
        XCTAssertEqual(harness.windowState.currentTabId, openedTab.id)
        XCTAssertNotNil(openedTab.resolvedAssignedWebView() ?? openedTab.resolvedCurrentWebView())
    }

    func testPopupCreateWebViewLeavesCommandClickNewTabInBackground() throws {
        let harness = try makePopupFocusHarness()
        harness.sourceTab.recordWebViewInteraction(
            makeMouseEvent(type: .leftMouseDown, modifierFlags: [.command])
        )
        let responder = SumiPopupHandlingNavigationResponder(tab: harness.sourceTab)
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: URL(string: "https://destination.example/page")!,
            webView: harness.sourceWebView,
            modifierFlags: [.command]
        )

        let childWebView = responder.createWebView(
            from: harness.sourceWebView,
            with: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNotNil(childWebView)
        XCTAssertEqual(harness.windowState.currentTabId, harness.sourceTab.id)
        XCTAssertEqual(harness.sourceTab.resolvedNavigationModifierFlags(actionFlags: []), [])
    }

    func testPolicyGeneratedCleanNewTabSelectsButCommandNewTabStaysBackground() {
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            ),
            .newTab(selected: true)
        )
        XCTAssertEqual(
            SumiLinkOpenBehavior(
                buttonIsMiddle: false,
                modifierFlags: [.command],
                switchToNewTabWhenOpenedPreference: false,
                canOpenLinkInCurrentTab: false,
                shouldSelectNewTab: true
            ),
            .newTab(selected: false)
        )
    }

    private func makePopupBrowserManager(needsWebViewCoordinator: Bool = false) throws -> BrowserManager {
        let moduleRegistry = makePopupModuleRegistry()
        moduleRegistry.setEnabled(false, for: .extensions)
        let browserManager = BrowserManager(
            moduleRegistry: moduleRegistry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: try Self.makeInMemoryStartupContainer()
            )
        )
        if needsWebViewCoordinator {
            browserManager.bindTestWebViewCoordinator()
        }
        return browserManager
    }

    private func makePopupModuleRegistry() -> SumiModuleRegistry {
        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: userDefaults)
        )
    }

    private static func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private struct PopupFocusHarness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let sourceSpace: Space
        let sourceTab: Tab
        let sourceWebView: WKWebView
    }

    private func makePopupFocusHarness() throws -> PopupFocusHarness {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = try makePopupBrowserManager(needsWebViewCoordinator: true)
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.sumiSettings = settings
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.selectTab(sourceTab, in: windowState)

        let sourceWebView = WKWebView(frame: .zero)
        browserManager.webViewOwnershipService?.assign(
            sourceWebView,
            to: sourceTab,
            in: windowState.id
        )
        sourceTab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: sourceTab.url)

        return PopupFocusHarness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            sourceSpace: space,
            sourceTab: sourceTab,
            sourceWebView: sourceWebView
        )
    }

    private func popupNavigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            SumiWKFrameInfoMock(
                isMainFrame: true,
                request: URLRequest(url: $0),
                securityOrigin: SumiWKSecurityOriginMock.new(url: $0),
                webView: webView
            ).frameInfo
        }
        let mock = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        )
        mock.isUserInitiated = true
        mock.modifierFlags = modifierFlags
        return mock.navigationAction
    }

    func testInternalSurfaceResponderCancelsRemoteWebNavigationToSumiSurface() async {
        let responder = SumiInternalSurfaceNavigationResponder()
        var preferences = sumiNavigationPreferences()
        let action = SumiNavigationAction(navigationAction(
            url: URL(string: "sumi://settings?pane=userScripts")!,
            navigationType: .other,
            sourceURL: URL(string: "https://evil.example/page")!,
            isUserInitiated: false,
            isMainFrame: true,
            targetFrameIsMainFrame: true
        ))

        let policy = await responder.decidePolicy(for: action, preferences: &preferences)

        XCTAssertEqual(policy, .cancel)
    }

    func testInternalSurfaceResponderAllowsUserEnteredSumiSurface() async {
        let responder = SumiInternalSurfaceNavigationResponder()
        var preferences = sumiNavigationPreferences()
        let action = SumiNavigationAction(navigationAction(
            url: URL(string: "sumi://settings?pane=privacy")!,
            navigationType: .custom(.sumiUserEnteredURL),
            sourceURL: URL(string: "about:blank")!,
            isUserInitiated: true,
            isMainFrame: true,
            targetFrameIsMainFrame: true
        ))

        let policy = await responder.decidePolicy(for: action, preferences: &preferences)

        XCTAssertNil(policy)
    }
}
