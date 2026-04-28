import Common
import Navigation
import WebKit
import XCTest

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
        XCTAssertTrue(popupResponderSource.contains("FocusableWKWebView(frame: .zero, configuration: configuration)"))
        XCTAssertTrue(popupResponderSource.contains("webViewConfigurationOverride: configuration"))
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
        XCTAssertEqual(bridge.attempts(forPageId: "tab-a:1").first?.result, .unsupportedScheme)
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

    private func navigationAction(
        url: URL,
        navigationType: NavigationType,
        shouldDownload: Bool = false,
        webView: WKWebView? = nil,
        sourceURL: URL? = nil,
        sourceSecurityOrigin: SecurityOrigin? = nil,
        isUserInitiated: Bool = true
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
            isMainFrame: true,
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
            normalizedScheme: scheme,
            appURL: URL(fileURLWithPath: "/Applications/\(scheme).app"),
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
        ],
        shouldPersist: false
    )
}
