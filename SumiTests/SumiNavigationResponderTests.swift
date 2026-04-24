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

        XCTAssertTrue(uiDelegateSource.contains("navigationDelegateBundle(for: webView)?.popupHandling.createWebView("))
        XCTAssertTrue(popupResponderSource.contains("FocusableWKWebView(frame: .zero, configuration: configuration)"))
        XCTAssertTrue(popupResponderSource.contains("webViewConfigurationOverride: configuration"))
        XCTAssertFalse(popupResponderSource.contains("loadURL(requestURL"))
        XCTAssertFalse(popupResponderSource.contains("load(URLRequest(url: requestURL"))
    }

    func testExternalSchemeResponderCancelsAndRoutesToWorkspace() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let workspace = RecordingWorkspace(applicationURL: URL(fileURLWithPath: "/Applications/Mail.app"))
        let responder = SumiExternalSchemeNavigationResponder(tab: tab, workspace: workspace)
        let mailURL = URL(string: "mailto:test@example.com")!
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(url: mailURL, navigationType: .linkActivated(isMiddleClick: false)),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertEqual(workspace.openedURLs, [mailURL])
    }

    func testExternalSchemeResponderCancelsUnknownExternalSchemeWithoutOpening() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let workspace = RecordingWorkspace(applicationURL: nil)
        let responder = SumiExternalSchemeNavigationResponder(tab: tab, workspace: workspace)
        var preferences = NavigationPreferences.default

        let policy = await responder.decidePolicy(
            for: navigationAction(
                url: URL(string: "unknown-scheme://payload")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertTrue(workspace.openedURLs.isEmpty)
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
        shouldDownload: Bool = false
    ) -> NavigationAction {
        let webView = WKWebView(frame: .zero)
        let frame = FrameInfo.mainFrame(for: webView)
        return NavigationAction(
            request: URLRequest(url: url),
            navigationType: navigationType,
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
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
private final class RecordingWorkspace: SumiWorkspaceOpening {
    private let applicationURL: URL?
    private(set) var openedURLs: [URL] = []

    init(applicationURL: URL?) {
        self.applicationURL = applicationURL
    }

    func urlForApplication(toOpen url: URL) -> URL? {
        applicationURL
    }

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}
