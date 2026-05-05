import AppKit
import Common
import SwiftData
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi

@MainActor
final class SumiNavigationResponderTests: XCTestCase {
    func testAssignWebViewInstallsDistributedNavigationDelegateBundle() {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let webView = WKWebView(frame: .zero)

        tab.assignWebViewToWindow(webView, windowId: UUID())

        XCTAssertTrue(webView.navigationDelegate is DistributedNavigationDelegate)
        XCTAssertNotNil(tab.navigationDelegateBundle(for: webView))
    }

    func testDistributedNavigationDecisionHandlerIsCalledExactlyOnceForCancelledPolicy() {
        let proxy = CountingNavigationDelegateProxy()
        let responder = ImmediatePolicyResponder(policy: .cancel)
        let webView = WKWebView(frame: .zero)
        let decisionHandlerCalled = expectation(description: "decision handler called")
        proxy.onActionDecision = { policy in
            XCTAssertEqual(policy, .cancel)
            decisionHandlerCalled.fulfill()
        }
        proxy.distributedNavigationDelegate.setResponders(.strong(responder))
        webView.navigationDelegate = proxy

        webView.load(URLRequest(url: URL(string: "https://example.com/cancel")!))

        wait(for: [decisionHandlerCalled], timeout: 5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(proxy.actionDecisionCount, 1)
        XCTAssertEqual(responder.policyCallCount, 1)
    }

    func testActionDecisionCompletesBeforeSlowLifecycleSideEffect() {
        let proxy = CountingNavigationDelegateProxy()
        let responder = SlowLifecycleProbeResponder()
        let schemeHandler = FailingSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: FailingSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let decisionHandlerCalled = expectation(description: "decision handler called")
        let willStartCalled = expectation(description: "willStart called")
        var decisionCountAtWillStart = 0
        proxy.onActionDecision = { policy in
            XCTAssertEqual(policy, .allow)
            decisionHandlerCalled.fulfill()
        }
        responder.onWillStart = {
            decisionCountAtWillStart = proxy.actionDecisionCount
            willStartCalled.fulfill()
            Thread.sleep(forTimeInterval: 0.05)
        }
        proxy.distributedNavigationDelegate.setResponders(.strong(responder))
        webView.navigationDelegate = proxy

        webView.load(URLRequest(url: URL(string: "\(FailingSchemeHandler.scheme)://example.com/slow")!))

        wait(for: [decisionHandlerCalled, willStartCalled], timeout: 5)
        XCTAssertEqual(proxy.actionDecisionCount, 1)
        XCTAssertEqual(decisionCountAtWillStart, 1)
        XCTAssertEqual(responder.policyCallCount, 1)
    }

    func testPopupRoutingKeepsWebKitProvidedConfigurationFlow() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let uiDelegateSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Sumi/Models/Tab/Tab+UIDelegate.swift"),
            encoding: .utf8
        )
        let popupResponderSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(uiDelegateSource.contains("popupHandling.createWebViewAsync("))
        XCTAssertTrue(uiDelegateSource.contains("completionHandler(popupWebView)"))
        XCTAssertTrue(popupResponderSource.contains("createPopupWebViewFromWebKitConfiguration("))
        XCTAssertFalse(popupResponderSource.contains("FocusableWKWebView(frame: .zero, configuration: configuration)"))
        XCTAssertFalse(popupResponderSource.contains("webViewConfigurationOverride: configuration"))
        XCTAssertTrue(popupResponderSource.contains("popupPermissionBridge.evaluate("))
        XCTAssertTrue(popupResponderSource.contains("evaluateSynchronouslyForWebKitFallback("))
        XCTAssertTrue(popupResponderSource.contains("guard permissionResult.isAllowed else { return nil }"))
        XCTAssertFalse(popupResponderSource.contains("loadURL(requestURL"))
        XCTAssertFalse(popupResponderSource.contains("load(URLRequest(url: requestURL"))
    }

    func testExternalSchemeResponderCancelsAndRoutesThroughPermissionBridge() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: NavigationExternalSchemeFakeCoordinator(
                decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
            ),
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() }
        )
        let mailURL = URL(string: "mailto:test@example.com")!
        let webView = WKWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(
                url: mailURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertEqual(resolver.openedURLs, [mailURL])
    }

    func testExternalSchemeResponderCancelsUnknownExternalSchemeWithoutOpening() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: [])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: NavigationExternalSchemeFakeCoordinator(
                decision: navigationExternalCoordinatorDecision(.granted, reason: "unused")
            ),
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() }
        )
        let webView = WKWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(
                url: URL(string: "unknown-scheme://payload")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        XCTAssertEqual(bridge.sessionStore.records(forPageId: "tab-a:1").first?.result, .unsupportedScheme)
    }

    func testExternalSchemeResponderSourceRoutesThroughBridgeBeforeAppOpen() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let responderSource = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Sumi/Models/Tab/Navigation/SumiExternalSchemeNavigationResponder.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(responderSource.contains("SumiExternalSchemePermissionRequest.fromNavigationAction"))
        XCTAssertTrue(responderSource.contains("bridge.evaluate("))
        XCTAssertTrue(responderSource.contains("return .cancel"))
        XCTAssertFalse(responderSource.contains("NSWorkspace.shared.open"))
        XCTAssertFalse(responderSource.contains("workspace.open"))
    }

    func testAutoplayPolicyResponderMapsStoredPoliciesToWebPagePreferences() async throws {
        let harness = try makeAutoplayHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let url = URL(string: "https://video.example/watch")!
        let cases: [(SumiAutoplayPolicy, _WKWebsiteAutoplayPolicy)] = [
            (.allowAll, .allow),
            (.blockAudible, .allowWithoutSound),
            (.blockAll, .deny),
        ]

        for (policy, expectedPolicy) in cases {
            try await harness.adapter.setPolicy(policy, for: url, profile: profile)
            let responder = makeAutoplayResponder(
                store: harness.adapter,
                profile: profile
            )
            var preferences = NavigationPreferences.default

            let decision = await responder.decidePolicy(
                for: navigationAction(
                    url: url,
                    navigationType: .linkActivated(isMiddleClick: false)
                ),
                preferences: &preferences
            )

            XCTAssertNil(decision)
            XCTAssertTrue(preferences.mustApplyAutoplayPolicy)
            XCTAssertEqual(preferences.autoplayPolicy, expectedPolicy)
        }
    }

    func testAutoplayPolicyResponderAppliesDefaultPolicyWhenNoSiteDecisionExists() async throws {
        let harness = try makeAutoplayHarness()
        let profile = makeProfile("bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee")
        let responder = makeAutoplayResponder(
            store: harness.adapter,
            profile: profile
        )
        var preferences = NavigationPreferences.default

        let decision = await responder.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://video.example/watch")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertNil(decision)
        XCTAssertTrue(preferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(preferences.autoplayPolicy, .allow)
    }

    func testAutoplayPolicyResponderIgnoresNonMainFrameAndNonWebNavigations() async throws {
        let harness = try makeAutoplayHarness()
        let profile = makeProfile("cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee")
        let responder = makeAutoplayResponder(
            store: harness.adapter,
            profile: profile
        )
        var nonMainPreferences = NavigationPreferences.default
        var filePreferences = NavigationPreferences.default

        _ = await responder.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://video.example/embed")!,
                navigationType: .other,
                isMainFrame: false
            ),
            preferences: &nonMainPreferences
        )
        _ = await responder.decidePolicy(
            for: navigationAction(
                url: URL(fileURLWithPath: "/tmp/autoplay.html"),
                navigationType: .other
            ),
            preferences: &filePreferences
        )

        XCTAssertFalse(nonMainPreferences.mustApplyAutoplayPolicy)
        XCTAssertNil(nonMainPreferences.autoplayPolicy)
        XCTAssertFalse(filePreferences.mustApplyAutoplayPolicy)
        XCTAssertNil(filePreferences.autoplayPolicy)
    }

    func testAutoplayPolicyResponderKeepsProfileDecisionsIsolated() async throws {
        let harness = try makeAutoplayHarness()
        let profileA = makeProfile("dddddddd-bbbb-cccc-dddd-eeeeeeeeeeee")
        let profileB = makeProfile("eeeeeeee-bbbb-cccc-dddd-eeeeeeeeeeee")
        let url = URL(string: "https://video.example/watch")!
        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profileA)
        let responder = makeAutoplayResponder(
            store: harness.adapter,
            profile: profileB
        )
        var preferences = NavigationPreferences.default

        _ = await responder.decidePolicy(
            for: navigationAction(
                url: url,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(preferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(preferences.autoplayPolicy, .allow)
    }

    func testAutoplayPolicyResponderIsRegisteredBeforeLifecycleResponder() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Sumi/Models/Tab/Navigation/SumiTabNavigationDelegateBundle.swift"
            ),
            encoding: .utf8
        )

        let autoplayIndex = try XCTUnwrap(source.range(of: ".strong(autoplayPolicy)")?.lowerBound)
        let lifecycleIndex = try XCTUnwrap(source.range(of: ".strong(lifecycle)")?.lowerBound)
        XCTAssertLessThan(autoplayIndex, lifecycleIndex)
    }

    func testDownloadResponderRequestsDownloadForDownloadNavigationAction() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/file.zip")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isDownload == true)
    }

    func testDownloadResponderRequestsDownloadForUnshowableResponse() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        let response = URLResponse(
            url: URL(string: "https://example.com/file.bin")!,
            mimeType: "application/octet-stream",
            expectedContentLength: 128,
            textEncodingName: nil
        )

        let policy = await responder.decidePolicy(
            for: NavigationResponse(
                response: response,
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: nil
            )
        )

        XCTAssertEqual(policy, .download)
    }

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

    func testDynamicGlanceIgnoresModifiedClicks() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.sumiSettings = settings
        let externalURL = URL(string: "https://destination.example/page")!
        let sameHostURL = URL(string: "https://source.example/other")!

        XCTAssertTrue(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: sameHostURL, modifierFlags: []))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.command]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option]))
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: [.option, .command]))

        settings.glanceEnabled = false
        XCTAssertFalse(tab.shouldOpenDynamicallyInGlance(url: externalURL, modifierFlags: []))
    }

    func testGlanceClickUsesEventModifierFlagsInsteadOfStaleClickState() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = BrowserManager()
        browserManager.sumiSettings = settings
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.browserManager = browserManager
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

    func testClearingSyntheticNewWindowClickStateDoesNotBreakPendingWindowPriority() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Models/Tab/Navigation/SumiPopupHandlingNavigationResponder.swift"
            ),
            encoding: .utf8
        )
        let asyncStart = try XCTUnwrap(source.range(of: "func createWebViewAsync(")?.lowerBound)
        let syncStart = try XCTUnwrap(source.range(of: "private func createWebViewSynchronously(", range: asyncStart..<source.endIndex)?.lowerBound)
        let policyStart = try XCTUnwrap(source.range(of: "func willStart", range: syncStart..<source.endIndex)?.lowerBound)
        let createWebViewSources = [
            String(source[asyncStart..<syncStart]),
            String(source[syncStart..<policyStart]),
        ]

        for createWebViewSource in createWebViewSources {
            let explicitGlance = try XCTUnwrap(createWebViewSource.range(of: "tab.isGlanceTriggerActive(navigationFlags)")?.lowerBound)
            let pendingWindow = try XCTUnwrap(createWebViewSource.range(of: "newWindowPolicy(for: navigationAction)")?.lowerBound)
            let dynamicGlance = try XCTUnwrap(createWebViewSource.range(of: "tab.shouldOpenDynamicallyInGlance(")?.lowerBound)

            XCTAssertLessThan(explicitGlance, pendingWindow)
            XCTAssertLessThan(pendingWindow, dynamicGlance)
        }
        XCTAssertTrue(source.contains("resetLinkGestureModifierState(for: tab)\n            targetWebView.sumiLoadInNewWindow(url)"))
    }

    func testPopupResponderOptionClickRoutesToGlance() async {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = BrowserManager()
        browserManager.sumiSettings = settings
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.browserManager = browserManager
        tab.sumiSettings = settings
        tab.setClickModifierFlags([.option])
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(
                url: targetURL,
                navigationType: .linkActivated(isMiddleClick: false),
                sourceURL: tab.url
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertEqual(browserManager.glanceManager.currentSession?.currentURL, targetURL)
    }

    func testPopupResponderCommandClickDoesNotRouteToGlance() async {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = BrowserManager()
        browserManager.sumiSettings = settings
        let tab = Tab(url: URL(string: "https://source.example/page")!)
        tab.browserManager = browserManager
        tab.sumiSettings = settings
        tab.setClickModifierFlags([.command])
        let responder = SumiPopupHandlingNavigationResponder(tab: tab)
        let targetURL = URL(string: "https://destination.example/page")!
        var preferences = NavigationPreferences.default

        _ = await responder.decidePolicy(
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

    private func navigationAction(
        url: URL,
        navigationType: NavigationType,
        shouldDownload: Bool = false,
        webView: WKWebView? = nil,
        sourceURL: URL? = nil,
        sourceSecurityOrigin: SecurityOrigin? = nil,
        isUserInitiated: Bool = true,
        isMainFrame: Bool = true
    ) -> NavigationAction {
        let webView = webView ?? WKWebView(frame: .zero)
        let frameURL = sourceURL ?? url
        let securityOrigin = sourceSecurityOrigin ?? SecurityOrigin(
            protocol: frameURL.scheme ?? "",
            host: frameURL.host ?? "",
            port: frameURL.port ?? 0
        )
        let frame = FrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: UInt64(1))!,
            isMainFrame: isMainFrame,
            url: frameURL,
            securityOrigin: securityOrigin
        )
        return NavigationAction(
            request: URLRequest(url: url),
            navigationType: navigationType,
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: isUserInitiated,
            sourceFrame: frame,
            targetFrame: frame,
            shouldDownload: shouldDownload,
            mainFrameNavigation: nil
        )
    }

    private func makeAutoplayHarness() throws -> (
        container: ModelContainer,
        adapter: SumiAutoplayPolicyStoreAdapter
    ) {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        return (
            container,
            SumiAutoplayPolicyStoreAdapter(
                modelContainer: container,
                persistentStore: store
            )
        )
    }

    private func makeAutoplayResponder(
        store: SumiAutoplayPolicyStoreAdapter,
        profile: Profile
    ) -> SumiAutoplayPolicyNavigationResponder {
        SumiAutoplayPolicyNavigationResponder(
            tab: Tab(url: URL(string: "https://video.example")!),
            autoplayPolicyStore: store,
            profileProvider: { _ in profile }
        )
    }

    private func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile", icon: "person")
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event")
        }
        return event
    }
}

private extension NavigationActionPolicy {
    var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }

    var isDownload: Bool {
        if case .download = self { return true }
        return false
    }
}

private extension NavigationPreferences {
    static var `default`: NavigationPreferences {
        NavigationPreferences(userAgent: nil, preferences: WKWebpagePreferences())
    }
}

@MainActor
private final class CountingNavigationDelegateProxy: NSObject, WKNavigationDelegate {
    let distributedNavigationDelegate = DistributedNavigationDelegate()
    var onActionDecision: ((WKNavigationActionPolicy) -> Void)?
    private(set) var actionDecisionCount = 0

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        distributedNavigationDelegate.webView(webView, decidePolicyFor: navigationAction, preferences: preferences) { [weak self] policy, preferences in
            self?.actionDecisionCount += 1
            self?.onActionDecision?(policy)
            decisionHandler(policy, preferences)
        }
    }
}

@MainActor
private final class ImmediatePolicyResponder: NavigationResponder {
    private let policy: NavigationActionPolicy
    private(set) var policyCallCount = 0

    init(policy: NavigationActionPolicy) {
        self.policy = policy
    }

    func decidePolicy(
        for _: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        policyCallCount += 1
        return policy
    }
}

@MainActor
private final class SlowLifecycleProbeResponder: NavigationResponder {
    var onWillStart: (() -> Void)?
    private(set) var policyCallCount = 0

    func decidePolicy(
        for _: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        policyCallCount += 1
        return .allow
    }

    func willStart(_: Navigation) {
        onWillStart?()
    }
}

private final class FailingSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "suminavtest"

    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFailWithError(NSError(domain: "SumiNavigationResponderTests", code: 1))
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {}
}

@MainActor
private final class NavigationExternalSchemeFakeResolver: SumiExternalAppResolving {
    private let handlerSchemes: Set<String>
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String>) {
        self.handlerSchemes = Set(handlerSchemes.map(SumiPermissionType.normalizedExternalScheme))
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        let scheme = SumiExternalSchemePermissionRequest.normalizedScheme(for: url)
        guard handlerSchemes.contains(scheme) else { return nil }
        return SumiExternalAppInfo(
            appDisplayName: "External App"
        )
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

private actor NavigationExternalSchemeFakeCoordinator: SumiPermissionCoordinating {
    private let decision: SumiPermissionCoordinatorDecision

    init(decision: SumiPermissionCoordinatorDecision) {
        self.decision = decision
    }

    func requestPermission(_: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        decision
    }

    func queryPermissionState(_: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        decision
    }

    func activeQuery(forPageId _: String) -> SumiPermissionAuthorizationQuery? {
        nil
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func cancel(requestId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }
}

private func navigationExternalTabContext() -> SumiExternalSchemePermissionTabContext {
    SumiExternalSchemePermissionTabContext(
        tabId: "tab-a",
        pageId: "tab-a:1",
        profilePartitionId: "profile-a",
        isEphemeralProfile: false,
        committedURL: URL(string: "https://top.example"),
        visibleURL: URL(string: "https://top.example/path"),
        mainFrameURL: URL(string: "https://top.example"),
        isActiveTab: true,
        isVisibleTab: true,
        navigationOrPageGeneration: "1"
    )
}

private func navigationExternalCoordinatorDecision(
    _ outcome: SumiPermissionCoordinatorOutcome,
    reason: String
) -> SumiPermissionCoordinatorDecision {
    let state: SumiPermissionState? = {
        switch outcome {
        case .granted:
            return .allow
        case .denied:
            return .deny
        case .promptRequired:
            return .ask
        default:
            return nil
        }
    }()
    return SumiPermissionCoordinatorDecision(
        outcome: outcome,
        state: state,
        persistence: outcome == .granted || outcome == .denied ? .persistent : nil,
        source: outcome == .granted || outcome == .denied ? .user : .defaultSetting,
        reason: reason,
        permissionTypes: [.externalScheme("mailto")],
        keys: [
            SumiPermissionKey(
                requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
                topOrigin: SumiPermissionOrigin(string: "https://top.example"),
                permissionType: .externalScheme("mailto"),
                profilePartitionId: "profile-a",
                transientPageId: "tab-a:1"
            ),
        ]
    )
}
