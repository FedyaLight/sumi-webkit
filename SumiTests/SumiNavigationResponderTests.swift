import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi

@MainActor
final class SumiNavigationResponderTests: XCTestCase {
    private var retainedAutoplayTabs: [Tab] = []

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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let mailURL = URL(string: "mailto:test@example.com")!
        let webView = WKWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: mailURL,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = WKWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "unknown-scheme://payload")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        XCTAssertEqual(bridge.sessionStore.records(forPageId: "tab-a:1").first?.result, .unsupportedScheme)
    }

    func testExternalSchemeResponderDerivesPermissionOriginFromNavigationSecurityOrigin() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let coordinator = NavigationExternalSchemeRecordingCoordinator()
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = WKWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "mailto:test@example.com")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://wrong.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        let contexts = await coordinator.recordedContexts()
        XCTAssertEqual(contexts.first?.requestingOrigin.identity, "https://request.example")
    }

    func testExternalSchemeResponderAdapterClosesInitialExternalAppOpenThroughSameWebViewClosePath() async {
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = SumiNavigationClosingTrackingWebView(frame: .zero)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "mailto:test@example.com")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!])
        XCTAssertEqual(webView.closeScriptEvaluations, 1)
    }

    func testExternalSchemeResponderAdapterDoesNotCloseAfterNavigationFinishOrFail() async {
        let finishedWebView = SumiNavigationClosingTrackingWebView(frame: .zero)
        let failedWebView = SumiNavigationClosingTrackingWebView(frame: .zero)

        await assertExternalSchemeOpenDoesNotCloseAfterCompletion(
            webView: finishedWebView,
            complete: { adapter, navigation in
                adapter.navigationDidFinish(navigation)
            }
        )
        await assertExternalSchemeOpenDoesNotCloseAfterCompletion(
            webView: failedWebView,
            complete: { adapter, navigation in
                adapter.navigation(navigation, didFailWith: WKError(.unknown))
            }
        )
    }

    func testPopupRequestDerivesPermissionOriginFromNavigationSecurityOrigin() {
        let action = navigationAction(
            url: URL(string: "https://popup.example/window")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: URL(string: "https://wrong.example/page")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
        )

        let request = SumiPopupPermissionRequest.fromNavigationAction(
            action,
            activationState: .navigationAction
        )

        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example")
    }

    func testNavigationFrameInfoBridgePreservesSourceOriginPortForPermissionOrigin() {
        let webView = WKWebView(frame: .zero)
        let sourceURL = URL(string: "https://request.example:8443/frame")!
        let handle = FrameHandle(rawValue: UInt64(2))!
        let frame = SumiSecurityOrigin(protocol: "https", host: "request.example", port: 8443)
            .navigationFrameInfo(
                webView: webView,
                handle: handle,
                isMainFrame: false,
                url: sourceURL
            )
        let sumiFrame = SumiNavigationFrameInfo(navigationFrame: frame)

        let origin = SumiSecurityOrigin(navigationFrame: sumiFrame)
            .permissionOrigin(missingReason: "missing-navigation-frame-origin")

        XCTAssertEqual(origin.kind, .web)
        XCTAssertEqual(origin.identity, "https://request.example:8443")
        XCTAssertEqual(sumiFrame.url, sourceURL)
        XCTAssertFalse(sumiFrame.isMainFrame)
        XCTAssertEqual(sumiFrame.handle?.frameID, handle.frameID)
    }

    func testNavigationFrameInfoBridgeFailsClosedForEmptySecurityOrigin() {
        let frame = SumiSecurityOrigin.empty.navigationFrameInfo(
            webView: WKWebView(frame: .zero),
            handle: FrameHandle(rawValue: UInt64(3))!,
            isMainFrame: true,
            url: URL(string: "about:blank")!
        )
        let sumiFrame = SumiNavigationFrameInfo(navigationFrame: frame)

        let origin = SumiSecurityOrigin(navigationFrame: sumiFrame)
            .permissionOrigin(missingReason: "missing-navigation-frame-origin")

        XCTAssertEqual(origin.kind, .invalid)
        XCTAssertEqual(origin.detail, "missing-navigation-frame-origin")
    }

    func testWebKitGeolocationRequestFailsClosedWhenFrameSafeRequestIsMissing() {
        let frame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://geo.example/frame")!),
            webView: WKWebView(frame: .zero)
        ).frameInfo

        let request = SumiWebKitGeolocationRequest(id: "missing-frame-request", frame: frame)

        XCTAssertEqual(request.requestingOrigin.kind, .invalid)
        XCTAssertEqual(request.requestingOrigin.detail, "missing-webkit-geolocation-frame-url")
        XCTAssertFalse(request.isMainFrame)
    }

    func testPopupRequestFromWKNavigationActionPreservesSourceFrameOriginWhenSafeRequestIsMissing() {
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://request.example:8443/frame")!),
            webView: WKWebView(frame: .zero)
        ).frameInfo
        let action = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: URL(string: "https://popup.example/window")!)
        ).navigationAction

        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            action,
            path: .navigationResponderTargetFrame,
            activationState: .navigationAction,
            isExtensionOriginated: false
        )

        XCTAssertEqual(request.targetURL, URL(string: "https://popup.example/window")!)
        XCTAssertNil(request.sourceURL)
        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example:8443")
        XCTAssertFalse(request.isMainFrame)
        XCTAssertEqual(request.navigationActionMetadata["targetFrameIsMainFrame"], "nil")
    }

    func testPopupRequestFromWKNavigationActionFailsClosedWhenSourceFrameIsMissing() {
        let action = SumiWKNavigationActionMock(
            sourceFrame: nil,
            targetFrame: nil,
            navigationType: .other,
            request: URLRequest(url: URL(string: "https://popup.example/window")!)
        ).navigationAction

        let request = SumiPopupPermissionRequest.fromWKNavigationAction(
            action,
            path: .navigationResponderTargetFrame,
            activationState: .none,
            isExtensionOriginated: false
        )

        XCTAssertEqual(request.targetURL, URL(string: "https://popup.example/window")!)
        XCTAssertNil(request.sourceURL)
        XCTAssertEqual(request.requestingOrigin.kind, .invalid)
        XCTAssertEqual(request.requestingOrigin.detail, "missing-url")
        XCTAssertTrue(request.isMainFrame)
    }

    func testPopupRequestPreservesPortedNavigationSourceFrameOriginAndFrameFlag() {
        let sourceURL = URL(string: "https://request.example:8443/frame")!
        let action = navigationAction(
            url: URL(string: "https://popup.example/window")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 8443),
            isMainFrame: false
        )

        let request = SumiPopupPermissionRequest.fromNavigationAction(
            action,
            activationState: .navigationAction
        )

        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example:8443")
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertFalse(request.isMainFrame)
        XCTAssertEqual(request.navigationActionMetadata["isForMainFrame"], "false")
    }

    func testExternalSchemeRequestPreservesPortedNavigationSourceFrameOriginAndFrameFlag() {
        let sourceURL = URL(string: "https://request.example:8443/frame")!
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 8443),
            isMainFrame: false
        )

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(action)

        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example:8443")
        XCTAssertEqual(request.userActivation, .navigationAction)
        XCTAssertEqual(request.classification, .directUserActivated)
        XCTAssertFalse(request.isMainFrame)
    }

    func testPopupRequestFromNavigationActionPreservesNewWindowMainFrameAndModifierMetadata() {
        let sourceURL = URL(string: "https://request.example/page")!
        let action = navigationAction(
            url: URL(string: "https://popup.example/window")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0),
            isTargetingNewWindow: true,
            modifierFlags: [.command, .shift]
        )
        let activationState = SumiPopupUserActivationTracker().activationState(
            webKitUserInitiated: nil,
            navigationActionUserInitiated: action.isUserInitiated
        )

        let request = SumiPopupPermissionRequest.fromNavigationAction(
            action,
            activationState: activationState
        )

        XCTAssertEqual(request.targetURL, URL(string: "https://popup.example/window")!)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example")
        XCTAssertTrue(request.isMainFrame)
        XCTAssertTrue(request.isUserActivated)
        XCTAssertEqual(request.classification, .directUserActivated)
        XCTAssertEqual(request.navigationActionMetadata["path"], SumiPopupPermissionPath.navigationResponderTargetFrame.rawValue)
        XCTAssertEqual(request.navigationActionMetadata["navigationType"], "linkActivated")
        XCTAssertEqual(request.navigationActionMetadata["activation"], "navigation-action")
        XCTAssertEqual(request.navigationActionMetadata["isTargetingNewWindow"], "true")
        XCTAssertEqual(request.navigationActionMetadata["isForMainFrame"], "false")
        XCTAssertEqual(
            request.navigationActionMetadata["modifierFlags"],
            "\(NSEvent.ModifierFlags([.command, .shift]).rawValue)"
        )
    }

    func testPopupRequestFromNavigationActionPreservesMainFrameTargetMetadata() {
        let sourceURL = URL(string: "https://request.example/page")!
        let action = navigationAction(
            url: URL(string: "https://destination.example/main")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0),
            targetFrameIsMainFrame: true,
            modifierFlags: []
        )

        let request = SumiPopupPermissionRequest.fromNavigationAction(
            action,
            activationState: .navigationAction
        )

        XCTAssertEqual(request.targetURL, URL(string: "https://destination.example/main")!)
        XCTAssertEqual(request.sourceURL, sourceURL)
        XCTAssertEqual(request.requestingOrigin.identity, "https://request.example")
        XCTAssertTrue(request.isMainFrame)
        XCTAssertEqual(request.navigationActionMetadata["isTargetingNewWindow"], "false")
        XCTAssertEqual(request.navigationActionMetadata["isForMainFrame"], "true")
        XCTAssertEqual(request.navigationActionMetadata["modifierFlags"], "0")
    }

    func testExternalSchemeRequestClassifiesNavigationTypeRedirectWithoutHistoryAsBackgroundRedirectChain() {
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .redirect(.server),
            sourceURL: URL(string: "https://redirect.example/page")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "redirect.example", port: 0),
            isUserInitiated: false
        )

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(action)

        XCTAssertEqual(request.targetURL, URL(string: "mailto:test@example.com")!)
        XCTAssertEqual(request.requestingOrigin.identity, "https://redirect.example")
        XCTAssertEqual(request.userActivation, .none)
        XCTAssertFalse(request.isUserActivated)
        XCTAssertEqual(request.classification, .redirectChainBackground)
        XCTAssertTrue(action.navigationType.isRedirect)
    }

    func testExternalSchemeRequestUsesRedirectHistoryInitialUserActivationForRedirectChain() {
        let initialAction = navigationAction(
            url: URL(string: "https://source.example/start")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: URL(string: "https://source.example/page")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "source.example", port: 0),
            isUserInitiated: true
        )
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .other,
            sourceURL: URL(string: "https://source.example/redirected")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "source.example", port: 0),
            isUserInitiated: false,
            redirectHistory: [initialAction]
        )

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(action)

        XCTAssertEqual(action.redirectHistory?.map(\.url), [URL(string: "https://source.example/start")!])
        XCTAssertFalse(action.navigationType.isLinkActivated)
        XCTAssertFalse(action.isUserInitiated)
        XCTAssertEqual(request.userActivation, .redirectChain)
        XCTAssertTrue(request.isUserActivated)
        XCTAssertEqual(request.classification, .redirectChainUserActivated)
    }

    func testExternalSchemeRequestUsesMainFrameNavigationRedirectHistoryForSubframeExternalRedirect() {
        let initialAction = navigationAction(
            url: URL(string: "https://source.example/start")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceURL: URL(string: "https://source.example/page")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "source.example", port: 0),
            isUserInitiated: true
        )
        let mainFrameAction = navigationAction(
            url: URL(string: "https://source.example/landing")!,
            navigationType: .redirect(.server),
            sourceURL: URL(string: "https://source.example/start")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "source.example", port: 0),
            isUserInitiated: false,
            redirectHistory: [initialAction]
        )
        let mainFrameNavigation = mainFrameNavigation(receiving: mainFrameAction)
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .other,
            sourceURL: URL(string: "https://frame.example/embed")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "frame.example", port: 0),
            isUserInitiated: false,
            isMainFrame: false,
            targetFrameIsMainFrame: false,
            mainFrameNavigation: mainFrameNavigation
        )

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(action)

        XCTAssertEqual(action.mainFrameNavigation?.navigationAction.redirectHistory?.map(\.url), [URL(string: "https://source.example/start")!])
        XCTAssertFalse(action.navigationType.isLinkActivated)
        XCTAssertFalse(action.isUserInitiated)
        XCTAssertFalse(action.isForMainFrame)
        XCTAssertEqual(request.requestingOrigin.identity, "https://frame.example")
        XCTAssertFalse(request.isMainFrame)
        XCTAssertEqual(request.userActivation, .redirectChain)
        XCTAssertEqual(request.classification, .redirectChainUserActivated)
    }

    func testExternalSchemeRequestTreatsUserInitiatedOtherNavigationAsDirectActivation() {
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .other,
            sourceURL: URL(string: "https://source.example/page")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "source.example", port: 0),
            isUserInitiated: true
        )

        let request = SumiExternalSchemePermissionRequest.fromNavigationAction(action)

        XCTAssertFalse(action.navigationType.isLinkActivated)
        XCTAssertTrue(action.isUserInitiated)
        XCTAssertEqual(request.userActivation, .navigationAction)
        XCTAssertEqual(request.classification, .directUserActivated)
    }

    func testSumiNavigationActionAdapterPreservesUsedNavigationMetadata() {
        let initialAction = navigationAction(
            url: URL(string: "https://source.example/start")!,
            navigationType: .linkActivated(isMiddleClick: true),
            sourceURL: URL(string: "https://source.example/page")!,
            isUserInitiated: true
        )
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .redirect(.server),
            sourceURL: URL(string: "https://frame.example/embed")!,
            sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "frame.example", port: 8443),
            isUserInitiated: false,
            isMainFrame: false,
            targetFrameIsMainFrame: false,
            redirectHistory: [initialAction],
            modifierFlags: [.option]
        )

        let sumiAction = SumiNavigationAction(action)

        XCTAssertEqual(sumiAction.url, URL(string: "mailto:test@example.com")!)
        XCTAssertEqual(sumiAction.sourceURL, URL(string: "https://frame.example/embed")!)
        XCTAssertEqual(sumiAction.sourceFrame?.securityOrigin.host, "frame.example")
        XCTAssertEqual(sumiAction.sourceFrame?.securityOrigin.port, 8443)
        XCTAssertFalse(sumiAction.isForMainFrame)
        XCTAssertFalse(sumiAction.isTargetingNewWindow)
        XCTAssertFalse(sumiAction.isUserInitiated)
        XCTAssertTrue(sumiAction.navigationType.isRedirect)
        XCTAssertEqual(sumiAction.navigationTypeDescription, "redirect(server)")
        XCTAssertEqual(sumiAction.redirectHistory.first?.url, URL(string: "https://source.example/start")!)
        XCTAssertTrue(sumiAction.redirectInitialAction?.isUserActivated == true)
        XCTAssertTrue(sumiAction.modifierFlags.contains(.option))
    }

    func testSumiNavigationActionWKAdapterPreservesSafeSourceFrameOriginWhenRequestIsMissing() {
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://request.example:8443/frame")!),
            webView: WKWebView(frame: .zero)
        ).frameInfo
        let action = SumiWKNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: URL(string: "https://popup.example/window")!)
        ).navigationAction

        let sumiAction = SumiNavigationAction(webKitNavigationAction: action)

        XCTAssertEqual(sumiAction.url, URL(string: "https://popup.example/window")!)
        XCTAssertNil(sumiAction.sourceURL)
        XCTAssertEqual(sumiAction.sourceFrame?.securityOrigin.host, "request.example")
        XCTAssertEqual(sumiAction.sourceFrame?.securityOrigin.port, 8443)
        XCTAssertFalse(sumiAction.sourceFrame?.isMainFrame ?? true)
        XCTAssertTrue(sumiAction.isTargetingNewWindow)
        XCTAssertEqual(sumiAction.navigationTypeDescription, "\(WKNavigationType.linkActivated.rawValue)")
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

        XCTAssertTrue(responderSource.contains("SumiExternalSchemePermissionRequest.fromSumiNavigationAction"))
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
            let adapter = SumiNavigationResponderAdapter(target: responder)
            var preferences = NavigationPreferences.default

            let decision = await adapter.decidePolicy(
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let decision = await adapter.decidePolicy(
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var nonMainPreferences = NavigationPreferences.default
        var filePreferences = NavigationPreferences.default

        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://video.example/embed")!,
                navigationType: .other,
                isMainFrame: false
            ),
            preferences: &nonMainPreferences
        )
        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(fileURLWithPath: "/tmp/autoplay.html"),
                navigationType: .other
            ),
            preferences: &filePreferences
        )

        XCTAssertFalse(nonMainPreferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(nonMainPreferences.autoplayPolicy, .default)
        XCTAssertFalse(filePreferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(filePreferences.autoplayPolicy, .default)
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        _ = await adapter.decidePolicy(
            for: navigationAction(
                url: url,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(preferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(preferences.autoplayPolicy, .allow)
    }

    func testAutoplayPolicyResponderIsRegisteredInOriginalResponderOrder() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Sumi/Models/Tab/Navigation/SumiTabNavigationDelegateBundle.swift"
            ),
            encoding: .utf8
        )

        let tokens = [
            ".strong(installNavigationAdapter)",
            ".strong(popupHandling)",
            ".strong(externalSchemeAdapter)",
            ".strong(downloadsAdapter)",
            ".strong(scriptAttachmentAdapter)",
            ".strong(autoplayPolicyAdapter)",
            ".strong(lifecycle)",
            ".weak(tab.findInPage)",
        ]
        let indices = try tokens.map { token in
            try XCTUnwrap(source.range(of: token)?.lowerBound, "Missing \(token)")
        }

        XCTAssertEqual(indices, indices.sorted())
    }

    func testSumiNavigationValueAdaptersRoundTripSimpleValues() {
        XCTAssertEqual(
            SumiNavigationActionPolicy.allCases.map { NavigationActionPolicy($0).sumiNavigationActionPolicy },
            SumiNavigationActionPolicy.allCases
        )
        XCTAssertEqual(
            SumiNavigationResponsePolicy.allCases.map { NavigationResponsePolicy($0).sumiNavigationResponsePolicy },
            SumiNavigationResponsePolicy.allCases
        )
        XCTAssertEqual(
            SumiSameDocumentNavigationType.allCases.map { WKSameDocumentNavigationType($0).sumiSameDocumentNavigationType },
            SumiSameDocumentNavigationType.allCases
        )

        let customType = SumiCustomNavigationType(rawValue: "sumi-test-custom-navigation")
        XCTAssertEqual(CustomNavigationType(customType).sumiCustomNavigationType, customType)
        XCTAssertEqual(
            SumiCustomNavigationType.userRequestedPageDownload.navigationCustomNavigationType.sumiCustomNavigationType,
            .userRequestedPageDownload
        )

        let credential = URLCredential(user: "sumi", password: "secret", persistence: .forSession)
        let credentialRoundTrip = AuthChallengeDisposition
            .credential(credential)
            .sumiAuthChallengeDisposition
            .navigationAuthChallengeDisposition
        guard case .credential(let roundTripCredential) = credentialRoundTrip else {
            return XCTFail("Expected credential auth challenge disposition")
        }
        XCTAssertEqual(roundTripCredential.user, credential.user)
        XCTAssertEqual(roundTripCredential.password, credential.password)
        XCTAssertEqual(SumiAuthChallengeDisposition.cancel.navigationAuthChallengeDisposition.sumiAuthChallengeDisposition.isCancel, true)
        XCTAssertEqual(
            SumiAuthChallengeDisposition.rejectProtectionSpace
                .navigationAuthChallengeDisposition
                .sumiAuthChallengeDisposition
                .isRejectProtectionSpace,
            true
        )

        let nextActionPolicy: SumiNavigationActionPolicy? = .next
        let nextResponsePolicy: SumiNavigationResponsePolicy? = .next
        let nextAuthDisposition: SumiAuthChallengeDisposition? = .next
        XCTAssertNil(nextActionPolicy)
        XCTAssertNil(nextResponsePolicy)
        XCTAssertNil(nextAuthDisposition)
    }

    func testSumiNavigationResponseAdapterCopiesURLResponseMetadata() {
        let url = URL(string: "https://example.com/report.pdf")!
        let response = NavigationResponse(
            response: URLResponse(
                url: url,
                mimeType: "application/pdf",
                expectedContentLength: 1024,
                textEncodingName: nil
            ),
            isForMainFrame: true,
            canShowMIMEType: true,
            mainFrameNavigation: nil
        )

        let value = SumiNavigationResponse(response)

        XCTAssertEqual(value.url, url)
        XCTAssertTrue(value.isForMainFrame)
        XCTAssertTrue(value.canShowMIMEType)
        XCTAssertFalse(value.shouldDownload)
        XCTAssertNil(value.httpResponse)
        XCTAssertNil(value.isHTTPStatusSuccessful)
        XCTAssertEqual(value.mimeType, "application/pdf")
        XCTAssertNil(value.mainFrameNavigation)
    }

    func testSumiNavigationResponseAdapterCopiesHTTPAndMainFrameNavigationMetadata() throws {
        let initialAction = navigationAction(
            url: URL(string: "https://example.com/start")!,
            navigationType: .linkActivated(isMiddleClick: false),
            requestCachePolicy: .returnCacheDataElseLoad
        )
        let finalAction = navigationAction(
            url: URL(string: "https://example.com/file.bin")!,
            navigationType: .custom(CustomNavigationType(.userRequestedPageDownload)),
            redirectHistory: [initialAction]
        )
        let navigation = mainFrameNavigation(receiving: finalAction)
        let httpResponse = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com/file.bin")!,
            statusCode: 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Disposition": "attachment; filename=file.bin"]
        ))
        let response = NavigationResponse(
            response: httpResponse,
            isForMainFrame: false,
            canShowMIMEType: true,
            mainFrameNavigation: navigation
        )

        let value = SumiNavigationResponse(response)

        XCTAssertEqual(value.url, httpResponse.url)
        XCTAssertFalse(value.isForMainFrame)
        XCTAssertTrue(value.canShowMIMEType)
        XCTAssertTrue(value.shouldDownload)
        XCTAssertEqual(value.httpResponse?.statusCode, 404)
        XCTAssertEqual(value.isHTTPStatusSuccessful, false)
        XCTAssertEqual(value.mainFrameNavigation?.redirectHistory.first?.request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(value.mainFrameNavigation?.navigationAction.navigationType, .custom(.userRequestedPageDownload))
    }

    func testActionResponderChainStopsAtFirstPolicyDecisionForAllowCancelDownload() async {
        let cases: [(SumiNavigationActionPolicy, String)] = [
            (.allow, "allow"),
            (.cancel, "cancel"),
            (.download, "download"),
        ]

        for (expectedPolicy, caseName) in cases {
            let first = ActionPolicyProbeResponder(name: "\(caseName)-first", decision: .next)
            let decider = ActionPolicyProbeResponder(
                name: "\(caseName)-decider",
                decision: expectedPolicy.navigationActionPolicy
            )
            let skipped = ActionPolicyProbeResponder(name: "\(caseName)-skipped", decision: .allow)
            var preferences = NavigationPreferences.default

            let policy = await evaluateActionPolicy(
                with: [first, decider, skipped],
                action: navigationAction(
                    url: URL(string: "https://example.com/\(caseName)")!,
                    navigationType: .linkActivated(isMiddleClick: false)
                ),
                preferences: &preferences
            )

            XCTAssertEqual(policy?.sumiNavigationActionPolicy, expectedPolicy)
            XCTAssertEqual(first.callCount, 1)
            XCTAssertEqual(decider.callCount, 1)
            XCTAssertEqual(skipped.callCount, 0)
        }
    }

    func testActionResponderChainCarriesPreferencesMutatedByContinuingResponder() async {
        let mutator = ActionPolicyProbeResponder(name: "mutator", decision: .next) { preferences in
            preferences.userAgent = "SumiNavigationParity/1"
            preferences.contentMode = .desktop
            preferences.javaScriptEnabled = false
        }
        let decider = ActionPolicyProbeResponder(name: "decider", decision: .allow)
        var preferences = NavigationPreferences.default

        let policy = await evaluateActionPolicy(
            with: [mutator, decider],
            action: navigationAction(
                url: URL(string: "https://example.com/preferences")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertActionPolicy(policy, .allow)
        XCTAssertEqual(decider.observedPreferences.first?.userAgent, "SumiNavigationParity/1")
        XCTAssertEqual(decider.observedPreferences.first?.contentMode, .desktop)
        XCTAssertEqual(decider.observedPreferences.first?.javaScriptEnabled, false)

        let appliedPreferences = preferences.applying(to: WKWebpagePreferences())
        XCTAssertEqual(appliedPreferences.preferredContentMode, .desktop)
        XCTAssertFalse(appliedPreferences.allowsContentJavaScript)
    }

    func testResponseResponderChainStopsAtFirstPolicyDecisionForAllowCancelDownload() async {
        let response = NavigationResponse(
            response: URLResponse(
                url: URL(string: "https://example.com/file.bin")!,
                mimeType: "application/octet-stream",
                expectedContentLength: 128,
                textEncodingName: nil
            ),
            isForMainFrame: true,
            canShowMIMEType: false,
            mainFrameNavigation: nil
        )
        let cases: [(SumiNavigationResponsePolicy, String)] = [
            (.allow, "allow"),
            (.cancel, "cancel"),
            (.download, "download"),
        ]

        for (expectedPolicy, caseName) in cases {
            let first = ResponsePolicyProbeResponder(name: "\(caseName)-first", decision: .next)
            let decider = ResponsePolicyProbeResponder(
                name: "\(caseName)-decider",
                decision: expectedPolicy.navigationResponsePolicy
            )
            let skipped = ResponsePolicyProbeResponder(name: "\(caseName)-skipped", decision: .allow)

            let policy = await evaluateResponsePolicy(
                with: [first, decider, skipped],
                response: response
            )

            XCTAssertEqual(policy?.sumiNavigationResponsePolicy, expectedPolicy)
            XCTAssertEqual(first.callCount, 1)
            XCTAssertEqual(decider.callCount, 1)
            XCTAssertEqual(skipped.callCount, 0)
        }
    }

    func testSumiNavigationResponderAdapterMapsNilActionAndResponseResultsToNext() async {
        let target = SumiNavigationAdapterProbeResponder(
            name: "next",
            actionDecision: .next,
            responseDecision: .next
        )
        let adapter = SumiNavigationResponderAdapter(target: target)
        var preferences = NavigationPreferences.default

        let actionPolicy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/next")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )
        let responsePolicy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://example.com/next")!,
                    mimeType: "text/html",
                    expectedContentLength: 32,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: nil
            )
        )

        XCTAssertNil(actionPolicy)
        XCTAssertNil(responsePolicy)
        XCTAssertEqual(target.actionCallCount, 1)
        XCTAssertEqual(target.responseCallCount, 1)
    }

    func testSumiNavigationResponderAdapterStopsAtFirstMappedActionPolicyForAllowCancelDownload() async {
        let cases: [(SumiNavigationActionPolicy, String)] = [
            (.allow, "allow"),
            (.cancel, "cancel"),
            (.download, "download"),
        ]

        for (expectedPolicy, caseName) in cases {
            let first = SumiNavigationAdapterProbeResponder(name: "\(caseName)-first", actionDecision: .next)
            let decider = SumiNavigationAdapterProbeResponder(name: "\(caseName)-decider", actionDecision: expectedPolicy)
            let skipped = SumiNavigationAdapterProbeResponder(name: "\(caseName)-skipped", actionDecision: .cancel)
            let adapters = [first, decider, skipped].map(SumiNavigationResponderAdapter.init(target:))
            var preferences = NavigationPreferences.default

            let policy = await evaluateActionPolicy(
                with: adapters,
                action: navigationAction(
                    url: URL(string: "https://example.com/adapter/action/\(caseName)")!,
                    navigationType: .linkActivated(isMiddleClick: false)
                ),
                preferences: &preferences
            )

            XCTAssertEqual(policy?.sumiNavigationActionPolicy, expectedPolicy)
            XCTAssertEqual(first.actionCallCount, 1)
            XCTAssertEqual(decider.actionCallCount, 1)
            XCTAssertEqual(skipped.actionCallCount, 0)
            XCTAssertEqual(decider.observedActions.first?.url, URL(string: "https://example.com/adapter/action/\(caseName)")!)
        }
    }

    func testSumiNavigationResponderAdapterStopsAtFirstMappedResponsePolicyForAllowCancelDownload() async {
        let response = NavigationResponse(
            response: URLResponse(
                url: URL(string: "https://example.com/adapter/response/file.bin")!,
                mimeType: "application/octet-stream",
                expectedContentLength: 128,
                textEncodingName: nil
            ),
            isForMainFrame: true,
            canShowMIMEType: false,
            mainFrameNavigation: nil
        )
        let cases: [(SumiNavigationResponsePolicy, String)] = [
            (.allow, "allow"),
            (.cancel, "cancel"),
            (.download, "download"),
        ]

        for (expectedPolicy, caseName) in cases {
            let first = SumiNavigationAdapterProbeResponder(name: "\(caseName)-first", responseDecision: .next)
            let decider = SumiNavigationAdapterProbeResponder(name: "\(caseName)-decider", responseDecision: expectedPolicy)
            let skipped = SumiNavigationAdapterProbeResponder(name: "\(caseName)-skipped", responseDecision: .cancel)
            let adapters = [first, decider, skipped].map(SumiNavigationResponderAdapter.init(target:))

            let policy = await evaluateResponsePolicy(
                with: adapters,
                response: response
            )

            XCTAssertEqual(policy?.sumiNavigationResponsePolicy, expectedPolicy)
            XCTAssertEqual(first.responseCallCount, 1)
            XCTAssertEqual(decider.responseCallCount, 1)
            XCTAssertEqual(skipped.responseCallCount, 0)
            XCTAssertEqual(decider.observedResponses.first?.url, URL(string: "https://example.com/adapter/response/file.bin")!)
        }
    }

    func testSumiNavigationResponderAdapterCarriesPreferencesMutatedByContinuingActionResponder() async {
        let mutator = SumiNavigationAdapterProbeResponder(name: "mutator", actionDecision: .next) { preferences in
            preferences.userAgent = "SumiNavigationAdapterParity/1"
            preferences.contentMode = .desktop
            preferences.javaScriptEnabled = false
            preferences.mustApplyAutoplayPolicy = true
            preferences.autoplayPolicy = .deny
        }
        let decider = SumiNavigationAdapterProbeResponder(name: "decider", actionDecision: .allow)
        let adapters = [mutator, decider].map(SumiNavigationResponderAdapter.init(target:))
        var preferences = NavigationPreferences.default

        let policy = await evaluateActionPolicy(
            with: adapters,
            action: navigationAction(
                url: URL(string: "https://example.com/adapter/preferences")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertActionPolicy(policy, .allow)
        XCTAssertEqual(decider.observedPreferences.first?.userAgent, "SumiNavigationAdapterParity/1")
        XCTAssertEqual(decider.observedPreferences.first?.contentMode, .desktop)
        XCTAssertEqual(decider.observedPreferences.first?.javaScriptEnabled, false)
        XCTAssertEqual(decider.observedPreferences.first?.mustApplyAutoplayPolicy, true)
        XCTAssertEqual(decider.observedPreferences.first?.autoplayPolicy, .deny)
        XCTAssertTrue(preferences.mustApplyAutoplayPolicy)
        XCTAssertEqual(preferences.autoplayPolicy, .deny)

        let appliedPreferences = preferences.applying(to: WKWebpagePreferences())
        XCTAssertEqual(appliedPreferences.preferredContentMode, .desktop)
        XCTAssertFalse(appliedPreferences.allowsContentJavaScript)
    }

    func testSumiNavigationResponderAdapterAwaitsAsyncRespondersInRegistrationOrder() async {
        let recorder = SumiNavigationAdapterOrderRecorder()
        let actionResponders = [
            SumiNavigationAdapterProbeResponder(name: "action-first", actionDecision: .next, recorder: recorder),
            SumiNavigationAdapterProbeResponder(name: "action-second", actionDecision: .next, recorder: recorder),
            SumiNavigationAdapterProbeResponder(name: "action-third", actionDecision: .allow, recorder: recorder),
        ]
        var preferences = NavigationPreferences.default

        let actionPolicy = await evaluateActionPolicy(
            with: actionResponders.map(SumiNavigationResponderAdapter.init(target:)),
            action: navigationAction(
                url: URL(string: "https://example.com/adapter/async-action")!,
                navigationType: .other
            ),
            preferences: &preferences
        )

        XCTAssertActionPolicy(actionPolicy, .allow)
        let actionEvents = recorder.snapshot()
        XCTAssertEqual(
            actionEvents,
            ["action-first", "action-second", "action-third"]
        )

        recorder.removeAll()
        let responseResponders = [
            SumiNavigationAdapterProbeResponder(name: "response-first", responseDecision: .next, recorder: recorder),
            SumiNavigationAdapterProbeResponder(name: "response-second", responseDecision: .download, recorder: recorder),
        ]
        let responsePolicy = await evaluateResponsePolicy(
            with: responseResponders.map(SumiNavigationResponderAdapter.init(target:)),
            response: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://example.com/adapter/async-response")!,
                    mimeType: "application/octet-stream",
                    expectedContentLength: 64,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: nil
            )
        )

        XCTAssertEqual(responsePolicy?.sumiNavigationResponsePolicy, .download)
        let responseEvents = recorder.snapshot()
        XCTAssertEqual(
            responseEvents,
            ["response-first", "response-second"]
        )
    }

    func testWeakSumiNavigationResponderAdapterDoesNotRetainTargetAndContinues() async {
        var target: SumiNavigationAdapterProbeResponder? = SumiNavigationAdapterProbeResponder(
            name: "temporary",
            actionDecision: .cancel,
            responseDecision: .download
        )
        weak var weakTarget = target
        let adapter = SumiNavigationResponderAdapter(target: target!)
        var preferences = NavigationPreferences.default

        target = nil

        XCTAssertNil(weakTarget)
        let actionPolicy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/adapter/deallocated")!,
                navigationType: .other
            ),
            preferences: &preferences
        )
        let responsePolicy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://example.com/adapter/deallocated")!,
                    mimeType: "text/html",
                    expectedContentLength: 16,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: nil
            )
        )
        XCTAssertNil(actionPolicy)
        XCTAssertNil(responsePolicy)
    }

    func testSumiNavigationResponderAdapterMapsNilAuthResultToNext() async {
        let target = SumiNavigationAuthProbeResponder(decision: .next)
        let adapter = SumiNavigationResponderAdapter(target: target)

        let disposition = await adapter.didReceive(makeAuthenticationChallenge(), for: nil)

        XCTAssertNil(disposition)
        XCTAssertEqual(target.callCount, 1)
        XCTAssertEqual(target.observedProtectionSpaceHosts, ["auth.example"])
    }

    func testSumiNavigationResponderAdapterMapsAuthDispositions() async {
        let credential = URLCredential(user: "sumi", password: "secret", persistence: .forSession)
        let cases: [(SumiAuthChallengeDisposition, AuthChallengeDisposition)] = [
            (.credential(credential), .credential(credential)),
            (.cancel, .cancel),
            (.rejectProtectionSpace, .rejectProtectionSpace),
        ]

        for (sumiDisposition, expectedDisposition) in cases {
            let target = SumiNavigationAuthProbeResponder(decision: sumiDisposition)
            let adapter = SumiNavigationResponderAdapter(target: target)

            let disposition = await adapter.didReceive(makeAuthenticationChallenge(), for: nil)

            XCTAssertAuthDisposition(disposition, expectedDisposition)
            XCTAssertEqual(target.callCount, 1)
        }
    }

    func testSumiNavigationResponderAdapterMapsSameDocumentNavigationType() {
        let target = SumiSameDocumentNavigationProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/page#section")!,
            navigationType: .sameDocumentNavigation(.anchorNavigation)
        ))

        for type in SumiSameDocumentNavigationType.allCases {
            adapter.navigation(
                navigation,
                didSameDocumentNavigationOf: WKSameDocumentNavigationType(type)
            )
        }

        XCTAssertEqual(target.observedTypes, SumiSameDocumentNavigationType.allCases)
    }

    func testSumiNavigationCompletionCallbacksBroadcastInAdapterOrderAndIgnoreNonConformingTargets() {
        let recorder = SumiNavigationAdapterOrderRecorder()
        let first = SumiNavigationCompletionProbeResponder(name: "first", recorder: recorder)
        let nonCompletion = SumiNavigationAdapterProbeResponder(name: "policy-only")
        let second = SumiNavigationCompletionProbeResponder(name: "second", recorder: recorder)
        let responders = [first, nonCompletion, second].map(SumiNavigationResponderAdapter.init(target:))
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/completion")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        for responder in responders {
            responder.navigationDidFinish(navigation)
        }
        for responder in responders {
            responder.navigation(navigation, didFailWith: WKError(.unknown))
        }

        XCTAssertEqual(
            recorder.snapshot(),
            ["first.finish", "second.finish", "first.fail", "second.fail"]
        )
    }

    func testWeakSumiNavigationCompletionAdapterIgnoresDeallocatedTarget() {
        let recorder = SumiNavigationAdapterOrderRecorder()
        var target: SumiNavigationCompletionProbeResponder? = SumiNavigationCompletionProbeResponder(
            name: "temporary",
            recorder: recorder
        )
        weak var weakTarget = target
        let adapter = SumiNavigationResponderAdapter(target: target!)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/deallocated-completion")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        target = nil

        XCTAssertNil(weakTarget)
        adapter.navigationDidFinish(navigation)
        adapter.navigation(navigation, didFailWith: WKError(.unknown))
        XCTAssertEqual(recorder.snapshot(), [])
    }

    func testSumiNavigationDownloadAdapterMapsActionAndResponseCallbacks() throws {
        let target = SumiNavigationDownloadProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let actionDownload = SumiWebKitDownloadMock(
            originalRequest: URLRequest(url: URL(string: "https://example.com/action-original.zip")!)
        )
        let responseDownload = SumiWebKitDownloadMock(
            originalRequest: URLRequest(url: URL(string: "https://example.com/response-original.zip")!)
        )
        let action = navigationAction(
            url: URL(string: "https://example.com/action.zip")!,
            navigationType: .linkActivated(isMiddleClick: false),
            shouldDownload: true
        )
        let httpResponse = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com/response.zip")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Disposition": "attachment; filename=response.zip"]
        ))
        let response = NavigationResponse(
            response: httpResponse,
            isForMainFrame: true,
            canShowMIMEType: false,
            mainFrameNavigation: mainFrameNavigation(receiving: action)
        )

        adapter.navigationAction(action, didBecome: actionDownload)
        adapter.navigationResponse(response, didBecome: responseDownload)

        XCTAssertEqual(target.actionDownloads.map(\.action.url), [URL(string: "https://example.com/action.zip")!])
        XCTAssertEqual(target.actionDownloads.first?.action.shouldDownload, true)
        XCTAssertNil(target.actionDownloads.first?.download.response)
        XCTAssertEqual(target.actionDownloads.first?.download.originalRequest?.url, URL(string: "https://example.com/action-original.zip")!)
        XCTAssertEqual(target.responseDownloads.map(\.response.url), [URL(string: "https://example.com/response.zip")!])
        XCTAssertEqual(target.responseDownloads.first?.response.shouldDownload, true)
        XCTAssertEqual(target.responseDownloads.first?.response.httpResponse?.statusCode, 200)
        XCTAssertEqual(target.responseDownloads.first?.download.response?.url, URL(string: "https://example.com/response.zip")!)
        XCTAssertEqual(target.responseDownloads.first?.download.originalRequest?.url, URL(string: "https://example.com/response-original.zip")!)
    }

    func testScriptAttachmentResponderAdapterAwaitsNormalTabScriptReplacementBeforeNextResponder() async throws {
        let tab = Tab(url: URL(string: "https://initial.example")!)
        let profile = Profile(name: "Script Adapter")
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: [
                SumiNavigationTestUserScript(source: "window.__sumiNavigationSeedScript = true;"),
            ]
        )
        let configuration = BrowserConfiguration().normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://initial.example")!,
            userScriptsProvider: scriptsProvider
        )
        let controller = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserContentController)
        XCTAssertTrue(controller.normalTabUserScriptsProvider === scriptsProvider)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let scriptAttachment = SumiTabScriptAttachmentNavigationResponder(tab: tab)
        let observer = SumiScriptAttachmentTimingProbeResponder(scriptsProvider: scriptsProvider)
        let responders = [
            SumiNavigationResponderAdapter(target: scriptAttachment),
            SumiNavigationResponderAdapter(target: observer),
        ]
        var preferences = NavigationPreferences.default

        let policy = await evaluateActionPolicy(
            with: responders,
            action: navigationAction(
                url: URL(string: "https://target.example")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView
            ),
            preferences: &preferences
        )

        XCTAssertActionPolicy(policy, .allow)
        XCTAssertEqual(scriptsProvider.scriptsRevision, 1)
        XCTAssertEqual(observer.observedScriptRevisions, [1])
    }

    func testDownloadResponderRequestsDownloadForDownloadNavigationAction() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/file.zip")!,
                navigationType: .linkActivated(isMiddleClick: false),
                shouldDownload: true
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isDownload == true)
    }

    func testDownloadResponderContinuesForRegularNavigationAction() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "https://example.com/page")!,
                navigationType: .linkActivated(isMiddleClick: false)
            ),
            preferences: &preferences
        )

        XCTAssertNil(policy)
    }

    func testDownloadResponderRequestsDownloadForUnshowableResponse() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let response = URLResponse(
            url: URL(string: "https://example.com/file.bin")!,
            mimeType: "application/octet-stream",
            expectedContentLength: 128,
            textEncodingName: nil
        )

        let policy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: response,
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: nil
            )
        )

        XCTAssertEqual(policy, .download)
    }

    func testDownloadResponderCancelsSessionRestorationCacheDownloadResponse() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let responder = SumiDownloadsNavigationResponder(tab: tab, downloadManager: nil)
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default
        let action = navigationAction(
            url: URL(string: "https://example.com/restored-file.bin")!,
            navigationType: .sessionRestoration,
            requestCachePolicy: .returnCacheDataElseLoad,
            isUserInitiated: false
        )

        _ = await adapter.decidePolicy(for: action, preferences: &preferences)
        let navigation = mainFrameNavigation(receiving: action)

        let policy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://example.com/restored-file.bin")!,
                    mimeType: "application/octet-stream",
                    expectedContentLength: 128,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: false,
                mainFrameNavigation: navigation
            )
        )

        XCTAssertEqual(policy, .cancel)
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
        requestCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        webView: WKWebView? = nil,
        sourceURL: URL? = nil,
        sourceSecurityOrigin: SumiSecurityOrigin? = nil,
        isUserInitiated: Bool = true,
        isMainFrame: Bool = true,
        targetFrameIsMainFrame: Bool? = nil,
        isTargetingNewWindow: Bool = false,
        redirectHistory: [NavigationAction]? = nil,
        mainFrameNavigation: Navigation? = nil,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NavigationAction {
        let webView = webView ?? WKWebView(frame: .zero)
        let frameURL = sourceURL ?? url
        let securityOrigin = sourceSecurityOrigin ?? SumiSecurityOrigin(
            protocol: frameURL.scheme ?? "",
            host: frameURL.host ?? "",
            port: frameURL.port ?? 0
        )
        let frame = securityOrigin.navigationFrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: UInt64(1))!,
            isMainFrame: isMainFrame,
            url: frameURL
        )
        let targetFrame = isTargetingNewWindow ? nil : securityOrigin.navigationFrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: UInt64(2))!,
            isMainFrame: targetFrameIsMainFrame ?? isMainFrame,
            url: frameURL
        )
        let request = URLRequest(url: url, cachePolicy: requestCachePolicy)
        var action = NavigationAction(
            request: request,
            navigationType: navigationType,
            currentHistoryItemIdentity: nil,
            redirectHistory: redirectHistory,
            isUserInitiated: isUserInitiated,
            sourceFrame: frame,
            targetFrame: targetFrame,
            shouldDownload: shouldDownload,
            mainFrameNavigation: mainFrameNavigation
        )
        action.modifierFlags = modifierFlags
        return action
    }

    private func mainFrameNavigation(receiving action: NavigationAction) -> Navigation {
        let navigation = Navigation(
            identity: NavigationIdentity(nil),
            responders: ResponderChain(),
            state: .expected(nil),
            isCurrent: false
        )
        navigation.navigationActionReceived(action)
        return navigation
    }

    private func evaluateActionPolicy(
        with responders: [any NavigationResponder & AnyObject],
        action: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        var chain = ResponderChain()
        chain.setResponders(responders.map { ResponderRefMaker.strong($0) })
        for responder in chain {
            if let policy = await responder.decidePolicy(for: action, preferences: &preferences) {
                return policy
            }
        }
        return .next
    }

    private func evaluateResponsePolicy(
        with responders: [any NavigationResponder & AnyObject],
        response: NavigationResponse
    ) async -> NavigationResponsePolicy? {
        var chain = ResponderChain()
        chain.setResponders(responders.map { ResponderRefMaker.strong($0) })
        for responder in chain {
            if let policy = await responder.decidePolicy(for: response) {
                return policy
            }
        }
        return .next
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
        let tab = Tab(url: URL(string: "https://video.example")!)
        retainedAutoplayTabs.append(tab)
        return SumiAutoplayPolicyNavigationResponder(
            tab: tab,
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

    private func assertExternalSchemeOpenDoesNotCloseAfterCompletion(
        webView: SumiNavigationClosingTrackingWebView,
        complete: (SumiNavigationResponderAdapter, Navigation) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
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
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://request.example/page")!,
            navigationType: .linkActivated(isMiddleClick: false),
            webView: webView
        ))
        var preferences = NavigationPreferences.default

        complete(adapter, navigation)

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "mailto:test@example.com")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertTrue(policy?.isCancel == true, file: file, line: line)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!], file: file, line: line)
        XCTAssertEqual(webView.closeScriptEvaluations, 0, file: file, line: line)
    }
}

private func XCTAssertActionPolicy(
    _ actual: NavigationActionPolicy?,
    _ expected: NavigationActionPolicy,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.some(.allow), .allow),
        (.some(.cancel), .cancel),
        (.some(.download), .download):
        break
    default:
        XCTFail(
            "Expected \(expected.debugDescription), got \(actual?.debugDescription ?? "nil")",
            file: file,
            line: line
        )
    }
}

private func XCTAssertAuthDisposition(
    _ actual: AuthChallengeDisposition?,
    _ expected: AuthChallengeDisposition,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.some(.credential(let actualCredential)), .credential(let expectedCredential)):
        XCTAssertEqual(actualCredential.user, expectedCredential.user, file: file, line: line)
        XCTAssertEqual(actualCredential.password, expectedCredential.password, file: file, line: line)
        XCTAssertEqual(actualCredential.persistence, expectedCredential.persistence, file: file, line: line)
    case (.some(.cancel), .cancel),
        (.some(.rejectProtectionSpace), .rejectProtectionSpace):
        break
    default:
        XCTFail("Expected \(expected), got \(String(describing: actual))", file: file, line: line)
    }
}

private func makeAuthenticationChallenge() -> URLAuthenticationChallenge {
    URLAuthenticationChallenge(
        protectionSpace: URLProtectionSpace(
            host: "auth.example",
            port: 443,
            protocol: "https",
            realm: "SumiNavigationResponderTests",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        ),
        proposedCredential: nil,
        previousFailureCount: 0,
        failureResponse: nil,
        error: nil,
        sender: SumiURLAuthenticationChallengeSenderMock()
    )
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

private extension SumiAuthChallengeDisposition {
    var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }

    var isRejectProtectionSpace: Bool {
        if case .rejectProtectionSpace = self { return true }
        return false
    }
}

private extension NavigationPreferences {
    static var `default`: NavigationPreferences {
        NavigationPreferences(userAgent: nil, preferences: WKWebpagePreferences())
    }
}

@MainActor
private final class SumiNavigationClosingTrackingWebView: WKWebView {
    private(set) var closeScriptEvaluations = 0

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: ((Any?, (any Error)?) -> Void)? = nil
    ) {
        if javaScriptString == "window.close()" {
            closeScriptEvaluations += 1
            completionHandler?(nil, nil)
            return
        }

        super.evaluateJavaScript(javaScriptString, completionHandler: completionHandler)
    }
}

private final class SumiWKNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType
    @objc var request: URLRequest
    @objc var shouldPerformDownload = false
    @objc var modifierFlags: NSEvent.ModifierFlags = []
    @objc var buttonNumber = 0
    @objc var isUserInitiated = false
    @objc var mainFrameNavigation: Any?

    init(
        sourceFrame: WKFrameInfo?,
        targetFrame: WKFrameInfo?,
        navigationType: WKNavigationType,
        request: URLRequest
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 }
        }.pointee
    }
}

private final class SumiWKFrameInfoMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        isMainFrame: Bool,
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}

@objc
private final class SumiWKSecurityOriginMock: WKSecurityOrigin {
    private var mockedProtocol = ""
    private var mockedHost = ""
    private var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    private func setURL(_ url: URL) {
        mockedProtocol = url.scheme ?? ""
        mockedHost = url.host ?? ""
        mockedPort = url.port ?? 0
    }

    static func new(url: URL) -> SumiWKSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! SumiWKSecurityOriginMock
        mock.setURL(url)
        return mock
    }
}

@MainActor
private final class ActionPolicyProbeResponder: NavigationResponder {
    private let name: String
    private let decision: NavigationActionPolicy?
    private let mutatePreferences: ((inout NavigationPreferences) -> Void)?
    private(set) var callCount = 0
    private(set) var observedActions: [NavigationAction] = []
    private(set) var observedPreferences: [NavigationPreferences] = []

    init(
        name: String,
        decision: NavigationActionPolicy?,
        mutatePreferences: ((inout NavigationPreferences) -> Void)? = nil
    ) {
        self.name = name
        self.decision = decision
        self.mutatePreferences = mutatePreferences
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        callCount += 1
        observedActions.append(navigationAction)
        observedPreferences.append(preferences)
        mutatePreferences?(&preferences)
        return decision
    }
}

@MainActor
private final class ResponsePolicyProbeResponder: NavigationResponder {
    private let name: String
    private let decision: NavigationResponsePolicy?
    private(set) var callCount = 0
    private(set) var observedResponses: [NavigationResponse] = []

    init(name: String, decision: NavigationResponsePolicy?) {
        self.name = name
        self.decision = decision
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        callCount += 1
        observedResponses.append(navigationResponse)
        return decision
    }
}

@MainActor
private final class SumiNavigationAdapterOrderRecorder {
    private var events: [String] = []

    func append(_ event: String) async {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }

    func appendSync(_ event: String) {
        events.append(event)
    }

    func removeAll() {
        events.removeAll()
    }
}

@MainActor
private final class SumiScriptAttachmentTimingProbeResponder: SumiNavigationActionResponding {
    private let scriptsProvider: SumiNormalTabUserScripts
    private(set) var observedScriptRevisions: [Int] = []

    init(scriptsProvider: SumiNormalTabUserScripts) {
        self.scriptsProvider = scriptsProvider
    }

    func decidePolicy(
        for _: SumiNavigationAction,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        observedScriptRevisions.append(scriptsProvider.scriptsRevision)
        return .allow
    }
}

@MainActor
private final class SumiNavigationAdapterProbeResponder: SumiNavigationActionResponding, SumiNavigationResponseResponding {
    private let name: String
    private let actionDecision: SumiNavigationActionPolicy?
    private let responseDecision: SumiNavigationResponsePolicy?
    private let recorder: SumiNavigationAdapterOrderRecorder?
    private let mutatePreferences: ((inout SumiNavigationPreferences) -> Void)?
    private(set) var actionCallCount = 0
    private(set) var responseCallCount = 0
    private(set) var observedActions: [SumiNavigationAction] = []
    private(set) var observedResponses: [SumiNavigationResponse] = []
    private(set) var observedPreferences: [SumiNavigationPreferences] = []

    init(
        name: String,
        actionDecision: SumiNavigationActionPolicy? = nil,
        responseDecision: SumiNavigationResponsePolicy? = nil,
        recorder: SumiNavigationAdapterOrderRecorder? = nil,
        mutatePreferences: ((inout SumiNavigationPreferences) -> Void)? = nil
    ) {
        self.name = name
        self.actionDecision = actionDecision
        self.responseDecision = responseDecision
        self.recorder = recorder
        self.mutatePreferences = mutatePreferences
    }

    init(
        name: String,
        actionDecision: SumiNavigationActionPolicy?,
        mutatePreferences: @escaping (inout SumiNavigationPreferences) -> Void
    ) {
        self.name = name
        self.actionDecision = actionDecision
        self.responseDecision = nil
        self.recorder = nil
        self.mutatePreferences = mutatePreferences
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        actionCallCount += 1
        observedActions.append(navigationAction)
        observedPreferences.append(preferences)
        await recorder?.append(name)
        mutatePreferences?(&preferences)
        return actionDecision
    }

    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        responseCallCount += 1
        observedResponses.append(navigationResponse)
        await recorder?.append(name)
        return responseDecision
    }
}

@MainActor
private final class SumiNavigationAuthProbeResponder: SumiNavigationAuthChallengeResponding {
    private let decision: SumiAuthChallengeDisposition?
    private(set) var callCount = 0
    private(set) var observedProtectionSpaceHosts: [String] = []

    init(decision: SumiAuthChallengeDisposition?) {
        self.decision = decision
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition? {
        callCount += 1
        observedProtectionSpaceHosts.append(authenticationChallenge.protectionSpace.host)
        return decision
    }
}

@MainActor
private final class SumiSameDocumentNavigationProbeResponder: SumiSameDocumentNavigationResponding {
    private(set) var observedTypes: [SumiSameDocumentNavigationType] = []

    func navigationDidSameDocumentNavigation(type: SumiSameDocumentNavigationType) {
        observedTypes.append(type)
    }
}

@MainActor
private final class SumiNavigationCompletionProbeResponder: SumiNavigationCompletionResponding {
    private let name: String
    private let recorder: SumiNavigationAdapterOrderRecorder

    init(name: String, recorder: SumiNavigationAdapterOrderRecorder) {
        self.name = name
        self.recorder = recorder
    }

    func navigationDidFinish() {
        recorder.appendSync("\(name).finish")
    }

    func navigationDidFail() {
        recorder.appendSync("\(name).fail")
    }
}

@MainActor
private final class SumiNavigationDownloadProbeResponder: SumiNavigationDownloadResponding {
    private(set) var actionDownloads: [(action: SumiNavigationAction, download: SumiNavigationDownload)] = []
    private(set) var responseDownloads: [(response: SumiNavigationResponse, download: SumiNavigationDownload)] = []

    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload) {
        actionDownloads.append((navigationAction, download))
    }

    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload) {
        responseDownloads.append((navigationResponse, download))
    }
}

private final class SumiWebKitDownloadMock: NSObject, WebKitDownload {
    let originalRequest: URLRequest?
    let originatingWebView: WKWebView?
    let targetWebView: WKWebView?
    weak var delegate: WKDownloadDelegate?
    private(set) var cancelCount = 0

    init(
        originalRequest: URLRequest?,
        originatingWebView: WKWebView? = nil,
        targetWebView: WKWebView? = nil
    ) {
        self.originalRequest = originalRequest
        self.originatingWebView = originatingWebView
        self.targetWebView = targetWebView
    }

    func cancel(_ completionHandler: ((Data?) -> Void)?) {
        cancelCount += 1
        completionHandler?(nil)
    }
}

private final class SumiURLAuthenticationChallengeSenderMock: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        _ = credential
        _ = challenge
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        _ = challenge
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
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
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

private final class SumiNavigationTestUserScript: NSObject, SumiUserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String] = []

    init(source: String) {
        self.source = source
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
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

private actor NavigationExternalSchemeRecordingCoordinator: SumiPermissionCoordinating {
    private var contexts: [SumiPermissionSecurityContext] = []

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return navigationExternalCoordinatorDecision(.promptRequired, reason: "recorded")
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return navigationExternalCoordinatorDecision(.promptRequired, reason: "recorded")
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

    func recordedContexts() -> [SumiPermissionSecurityContext] {
        contexts
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
