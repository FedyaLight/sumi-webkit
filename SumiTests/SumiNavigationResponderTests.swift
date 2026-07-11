import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi
import SumiDomain

@MainActor
final class SumiNavigationResponderTests: SumiNavigationResponderTestCase {

    func testAssignWebViewInstallsSumiNavigationDelegateAdapter() {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let webView = WKWebView(frame: .zero)

        tab.prepareAssignedWebView(webView)

        let adapter = tab.navigationDelegateBundle(for: webView)
        XCTAssertNotNil(adapter)
        XCTAssertEqual(adapter?.isInstalled(on: webView), true)
        XCTAssertEqual(adapter?.hasResponder(SafariExtensionInlineUINavigationResponder.self), true)
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
        tab.webViewSession.replaceUntracked(with: webView)
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

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(resolver.openedURLs, [mailURL])
    }

    func testExternalSchemeResponderUsesInjectedRuntimeWithoutBrowserManager() async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: NavigationExternalSchemeFakeCoordinator(
                decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
            ),
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        tab.navigationRuntime.navigationDelegateRuntime = TabNavigationDelegateRuntime(
            externalSchemePermissionBridge: { bridge },
            downloadManager: { nil }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: tab,
            tabContextProvider: { _ in navigationExternalTabContext() }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let mailURL = URL(string: "mailto:test@example.com")!
        let webView = WKWebView(frame: .zero)
        tab.webViewSession.replaceUntracked(with: webView)
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

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(policy?.isCancel, true)
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

        XCTAssertEqual(policy?.isCancel, true)
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
        tab.webViewSession.replaceUntracked(with: webView)
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

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!])
        XCTAssertEqual(webView.closeScriptEvaluations, 1)
    }

    func testExternalSchemeUsesSourcePermissionContextAndClosesCrossWebViewTarget() async {
        let sourceTab = Tab(url: URL(string: "https://request.example/page")!)
        let targetTab = Tab(url: SumiSurface.emptyTabURL)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: NavigationExternalSchemeFakeCoordinator(
                decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
            ),
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let sourceWebView = FocusableWKWebView()
        let targetWebView = SumiNavigationClosingTrackingWebView(frame: .zero)
        sourceWebView.owningTab = sourceTab
        sourceTab.webViewSession.replaceUntracked(with: sourceWebView)
        targetTab.webViewSession.replaceUntracked(with: targetWebView)
        let sourceLease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(sourceWebView),
            participantID: UUID(),
            committedURL: URL(string: "https://request.example/page")!,
            presentationURL: URL(string: "https://request.example/page")!,
            isPDF: false,
            isAuthority: true
        )
        var permissionContextWebView: WKWebView?
        let responder = SumiExternalSchemeNavigationResponder(
            tab: targetTab,
            permissionBridge: bridge,
            tabContextProvider: { webView in
                permissionContextWebView = webView
                return navigationExternalTabContext()
            },
            documentLeaseProvider: { _, webView in
                webView === sourceWebView ? sourceLease : nil
            }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        var preferences = NavigationPreferences.default

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "mailto:test@example.com")!,
                navigationType: .linkActivated(isMiddleClick: false),
                sourceWebView: sourceWebView,
                targetWebView: targetWebView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(
                    protocol: "https",
                    host: "request.example",
                    port: 0
                )
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertIdentical(permissionContextWebView, sourceWebView)
        XCTAssertEqual(targetWebView.closeScriptEvaluations, 1)
    }

    func testExternalSchemeDoesNotCloseTargetRepurposedWhilePermissionIsPending() async {
        let sourceTab = Tab(url: URL(string: "https://request.example/page")!)
        let targetTab = Tab(url: SumiSurface.emptyTabURL)
        let sourceWebView = FocusableWKWebView()
        let targetWebView = SumiNavigationClosingTrackingWebView(frame: .zero)
        sourceWebView.owningTab = sourceTab
        sourceTab.webViewSession.replaceUntracked(with: sourceWebView)
        targetTab.webViewSession.replaceUntracked(with: targetWebView)
        let sourceURL = URL(string: "https://request.example/page")!
        let sourceLease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(sourceWebView),
            participantID: UUID(),
            committedURL: sourceURL,
            presentationURL: sourceURL,
            isPDF: false,
            isAuthority: true
        )
        let coordinator = NavigationExternalSchemeControlledCoordinator(
            decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
        )
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: targetTab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() },
            documentLeaseProvider: { _, webView in
                webView === sourceWebView ? sourceLease : nil
            }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceWebView: sourceWebView,
            targetWebView: targetWebView,
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(
                protocol: "https",
                host: "request.example",
                port: 0
            )
        )

        let decision = Task { @MainActor in
            var preferences = NavigationPreferences.default
            return await adapter.decidePolicy(
                for: action,
                preferences: &preferences
            )
        }
        await coordinator.waitForQuery()

        let repurposedURL = URL(string: "https://replacement.example/page")!
        targetWebView.reportedCommittedURL = repurposedURL
        let repurposedNavigation = NSObject()
        responder.navigationDidCommit(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(repurposedNavigation),
                navigationLifetime: repurposedNavigation,
                action: nil,
                url: repurposedURL,
                isCurrent: true,
                isCommitted: true,
                isMainFrame: true,
                webView: targetWebView
            )
        )
        await coordinator.releaseQuery()

        let policy = await decision.value
        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!])
        XCTAssertEqual(targetWebView.closeScriptEvaluations, 0)
    }

    func testExternalSchemeDoesNotCloseTargetAfterSourceDocumentLeaseChangesWhilePermissionIsPending() async {
        let sourceTab = Tab(url: URL(string: "https://request.example/page")!)
        let targetTab = Tab(url: SumiSurface.emptyTabURL)
        let sourceWebView = FocusableWKWebView()
        let targetWebView = SumiNavigationClosingTrackingWebView(frame: .zero)
        sourceWebView.owningTab = sourceTab
        sourceTab.webViewSession.replaceUntracked(with: sourceWebView)
        targetTab.webViewSession.replaceUntracked(with: targetWebView)
        let sourceURL = URL(string: "https://request.example/page")!
        var sourceLease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(sourceWebView),
            participantID: UUID(),
            committedURL: sourceURL,
            presentationURL: sourceURL,
            isPDF: false,
            isAuthority: true
        )
        let coordinator = NavigationExternalSchemeControlledCoordinator(
            decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
        )
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: targetTab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() },
            documentLeaseProvider: { _, webView in
                webView === sourceWebView ? sourceLease : nil
            }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let action = navigationAction(
            url: URL(string: "mailto:test@example.com")!,
            navigationType: .linkActivated(isMiddleClick: false),
            sourceWebView: sourceWebView,
            targetWebView: targetWebView,
            sourceURL: sourceURL,
            sourceSecurityOrigin: SumiSecurityOrigin(
                protocol: "https",
                host: "request.example",
                port: 0
            )
        )

        let decision = Task { @MainActor in
            var preferences = NavigationPreferences.default
            return await adapter.decidePolicy(
                for: action,
                preferences: &preferences
            )
        }
        await coordinator.waitForQuery()

        sourceLease = TabMainFrameDocumentLease(
            revision: 2,
            documentGeneration: 2,
            webViewID: ObjectIdentifier(sourceWebView),
            participantID: UUID(),
            committedURL: URL(string: "https://replacement.example/page")!,
            presentationURL: URL(string: "https://replacement.example/page")!,
            isPDF: false,
            isAuthority: true
        )
        await coordinator.releaseQuery()

        let policy = await decision.value
        XCTAssertEqual(policy?.isCancel, true)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!])
        XCTAssertEqual(targetWebView.closeScriptEvaluations, 0)
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

        let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
            SumiNavigationAction(action),
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
        let webView = WKWebView(frame: .zero)
        let frame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://geo.example/frame")!),
            webView: webView
        ).frameInfo

        let request = SumiWebKitGeolocationRequest(id: "missing-frame-request", frame: frame)

        XCTAssertEqual(request.requestingOrigin.kind, .invalid)
        XCTAssertEqual(request.requestingOrigin.detail, "missing-webkit-geolocation-frame-url")
        XCTAssertFalse(request.isMainFrame)
    }

    func testPopupRequestFromWKNavigationActionPreservesSourceFrameOriginWhenSafeRequestIsMissing() {
        let webView = WKWebView(frame: .zero)
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://request.example:8443/frame")!),
            webView: webView
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

        let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
            SumiNavigationAction(action),
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

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(SumiNavigationAction(action))

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

        let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
            SumiNavigationAction(action),
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

        let request = SumiPopupPermissionRequest.fromSumiNavigationAction(
            SumiNavigationAction(action),
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

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(SumiNavigationAction(action))

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

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(SumiNavigationAction(action))

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

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(SumiNavigationAction(action))

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

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(SumiNavigationAction(action))

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
        XCTAssertEqual(sumiAction.redirectInitialAction?.isUserActivated, true)
        XCTAssertTrue(sumiAction.modifierFlags.contains(.option))
    }

    func testSumiNavigationActionWKAdapterPreservesSafeSourceFrameOriginWhenRequestIsMissing() {
        let webView = WKWebView(frame: .zero)
        let sourceFrame = SumiWKFrameInfoMock(
            isMainFrame: false,
            request: nil,
            securityOrigin: SumiWKSecurityOriginMock.new(url: URL(string: "https://request.example:8443/frame")!),
            webView: webView
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

    func testSumiNavigationValueAdaptersMapProductDirections() {
        XCTAssertEqual(SumiNavigationActionPolicy.allCases.map(\.navigationActionPolicy), [.allow, .cancel, .download])
        XCTAssertEqual(SumiNavigationResponsePolicy.allCases.map(\.navigationResponsePolicy), [.allow, .cancel, .download])
        XCTAssertEqual(
            (0...3).map { WKSameDocumentNavigationType(rawValue: $0)!.sumiSameDocumentNavigationType },
            SumiSameDocumentNavigationType.allCases
        )
        XCTAssertEqual(
            SumiCustomNavigationType.userRequestedPageDownload.navigationCustomNavigationType.rawValue,
            "userRequestedPageDownload"
        )

        let credential = URLCredential(user: "sumi", password: "secret", persistence: .forSession)
        let credentialDisposition = SumiAuthChallengeDisposition.credential(credential).navigationAuthChallengeDisposition
        guard case .credential(let mappedCredential) = credentialDisposition else {
            return XCTFail("Expected credential auth challenge disposition")
        }
        XCTAssertEqual(mappedCredential.user, credential.user)
        XCTAssertEqual(mappedCredential.password, credential.password)
        XCTAssertAuthDisposition(SumiAuthChallengeDisposition.cancel.navigationAuthChallengeDisposition, .cancel)
        XCTAssertAuthDisposition(
            SumiAuthChallengeDisposition.rejectProtectionSpace.navigationAuthChallengeDisposition,
            .rejectProtectionSpace
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

    func testInstallNavigationResponderUsesInjectedRuntimeWithoutBrowserManager() async {
        let installURL = URL(string: "https://userscripts.example/install.user.js")!
        let tab = Tab(loadsCachedFaviconOnInit: false)
        var interceptedURLs: [URL] = []
        tab.navigationRuntime.installNavigationRuntime = TabInstallNavigationRuntime(
            interceptInstallNavigation: { url in
                interceptedURLs.append(url)
                return url == installURL
            }
        )
        let responder = SumiInstallNavigationResponder(tab: tab)
        var preferences = sumiNavigationPreferences()

        let actionPolicy = await responder.decidePolicy(
            for: SumiNavigationAction(
                navigationAction(
                    url: installURL,
                    navigationType: .linkActivated(isMiddleClick: false),
                    isMainFrame: true
                )
            ),
            preferences: &preferences
        )
        let responsePolicy = await responder.decidePolicy(
            for: SumiNavigationResponse(
                url: installURL,
                isForMainFrame: true,
                canShowMIMEType: true,
                shouldDownload: false,
                httpResponse: nil,
                mimeType: "application/javascript",
                mainFrameNavigation: nil
            )
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(actionPolicy, .cancel)
        XCTAssertEqual(responsePolicy, .cancel)
        XCTAssertEqual(interceptedURLs, [installURL, installURL])
    }

    func testPDFPresentationChangesOnlyWhenExactMainFrameResponseCommits() async {
        let tab = Tab(url: URL(string: "https://example.com/start")!)
        let responder = tab.makeMainFrameLifecycleResponder()
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        let pdfURL = URL(string: "https://example.com/report.pdf")!
        webView.reportedURL = pdfURL
        let pdfNavigation = mainFrameNavigation(
            receiving: navigationAction(
                url: pdfURL,
                navigationType: .other,
                webView: webView
            ),
            isCurrent: true
        )
        adapter.willStart(pdfNavigation)

        let pdfPolicy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: pdfURL,
                    mimeType: "application/pdf",
                    expectedContentLength: 1024,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: pdfNavigation
            )
        )

        XCTAssertNil(pdfPolicy)
        XCTAssertNotEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pdfDocument)
        )
        adapter.didCommit(pdfNavigation)
        XCTAssertEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pdfDocument)
        )

        let subframePolicy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: URL(string: "https://cdn.example.com/embed.html")!,
                    mimeType: "text/html",
                    expectedContentLength: 128,
                    textEncodingName: nil
                ),
                isForMainFrame: false,
                canShowMIMEType: true,
                mainFrameNavigation: nil
            )
        )

        XCTAssertNil(subframePolicy)
        XCTAssertEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pdfDocument)
        )

        adapter.navigationDidFinish(pdfNavigation)
        let htmlURL = URL(string: "https://example.com/page")!
        webView.reportedURL = htmlURL
        let htmlNavigation = mainFrameNavigation(
            receiving: navigationAction(
                url: htmlURL,
                navigationType: .other,
                webView: webView
            ),
            isCurrent: true
        )
        adapter.willStart(htmlNavigation)

        let htmlPolicy = await adapter.decidePolicy(
            for: NavigationResponse(
                response: URLResponse(
                    url: htmlURL,
                    mimeType: "text/html",
                    expectedContentLength: 256,
                    textEncodingName: nil
                ),
                isForMainFrame: true,
                canShowMIMEType: true,
                mainFrameNavigation: htmlNavigation
            )
        )

        XCTAssertNil(htmlPolicy)
        adapter.didCommit(htmlNavigation)
        XCTAssertNotEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pdfDocument)
        )
    }

    func testTabLifecycleWillStartUsesInjectedRuntimeWithoutBrowserManager() {
        let destinationURL = URL(string: "https://example.com/page")!
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabLifecycleNavigationRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = lifecycle.runtime
        let responder = tab.makeMainFrameLifecycleResponder()
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        let navigation = NSObject()

        responder.navigationWillStart(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                action: nil,
                url: destinationURL,
                isCurrent: true,
                isMainFrame: true,
                webView: webView
            )
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(lifecycle.resetRevisitProtectionTabIds, [tab.id])
        XCTAssertEqual(lifecycle.preparedExtensionWebViewIds, [ObjectIdentifier(webView)])
        XCTAssertEqual(lifecycle.preparedExtensionURLs, [destinationURL])
        XCTAssertEqual(lifecycle.preparedExtensionReasons, ["SumiTabLifecycleNavigationResponder.start"])
        XCTAssertEqual(lifecycle.beforeCommitTabIds, [tab.id])
        XCTAssertEqual(lifecycle.beforeCommitURLs, [destinationURL])
    }

    func testTabLifecycleWillStartResetsOnlyExactSourceCloneInteractionState() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let responder = tab.makeMainFrameLifecycleResponder()
        let sourceWebView = FocusableWKWebView()
        let siblingClone = FocusableWKWebView()
        let sourceEvent = makeMouseEvent(
            type: .leftMouseDown,
            modifierFlags: [.command]
        )
        let siblingEvent = makeMouseEvent(
            type: .leftMouseDown,
            modifierFlags: [.option]
        )
        sourceWebView.gestures.record(sourceEvent, kind: .primaryMouseDown)
        siblingClone.gestures.record(siblingEvent, kind: .primaryMouseDown)
        sourceWebView.hoveredLink.update("https://source.example/link")
        siblingClone.hoveredLink.update("https://sibling.example/link")
        sourceWebView.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(kind: .link)
        )
        siblingClone.contextMenu.record(
            SumiWebPageContextMenuTargetSnapshot(kind: .editable)
        )
        sourceWebView.popupUserActivation.record(
            event: sourceEvent,
            kind: "leftMouseDown"
        )
        siblingClone.popupUserActivation.record(
            event: siblingEvent,
            kind: "leftMouseDown"
        )
        let navigation = NSObject()

        responder.navigationWillStart(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                action: nil,
                url: URL(string: "https://destination.example/page")!,
                isCurrent: true,
                isMainFrame: true,
                webView: sourceWebView
            )
        )

        XCTAssertEqual(sourceWebView.gestures.resolvedModifierFlags(actionFlags: []), [])
        XCTAssertNil(sourceWebView.hoveredLink.href)
        XCTAssertNil(sourceWebView.contextMenu.recentTarget())
        XCTAssertFalse(
            sourceWebView.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
        XCTAssertEqual(
            siblingClone.gestures.resolvedModifierFlags(actionFlags: []),
            [.option]
        )
        XCTAssertEqual(siblingClone.hoveredLink.href, "https://sibling.example/link")
        XCTAssertEqual(siblingClone.contextMenu.recentTarget()?.kind, .editable)
        XCTAssertTrue(
            siblingClone.popupUserActivation
                .activationState(webKitUserInitiated: false)
                .isUserActivated
        )
    }

    func testTabLifecycleDidFinishUsesInjectedRuntimesWithoutBrowserManager() {
        let finalURL = URL(string: "https://example.com/finished")!
        let tab = Tab(url: URL(string: "https://example.com/start")!, loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabLifecycleNavigationRuntime()
        let extensionProperties = NavigationRecordingTabExtensionPropertiesRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = lifecycle.runtime
        tab.navigationRuntime.extensionPropertiesRuntime = extensionProperties.runtime
        let responder = tab.makeMainFrameLifecycleResponder()
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = finalURL
        let navigation = NSObject()
        let context = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: finalURL,
            isCurrent: true,
            isMainFrame: true,
            webView: webView
        )

        responder.navigationWillStart(context)
        responder.navigationDidFinish(context)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(tab.url, finalURL)
        XCTAssertEqual(lifecycle.zoomTabIds, [tab.id])
        XCTAssertEqual(lifecycle.adblockWebViewIds, [ObjectIdentifier(webView)])
        XCTAssertEqual(lifecycle.adblockURLs, [finalURL])
        XCTAssertEqual(lifecycle.siteDataPolicyTabIds, [tab.id])
        XCTAssertEqual(lifecycle.documentSuspensionReconcileTabIds, [tab.id])
        XCTAssertEqual(extensionProperties.tabIds, [tab.id, tab.id, tab.id, tab.id])
        XCTAssertEqual(extensionProperties.properties, [
            [.loading],
            [.URL, .loading],
            [.loading],
            [.URL, .title, .loading],
        ])
    }

    func testTabLifecycleAuthChallengeUsesInjectedRuntimeWithoutBrowserManager() async {
        let credential = URLCredential(
            user: "alice",
            password: "secret",
            persistence: .forSession
        )
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabLifecycleNavigationRuntime()
        lifecycle.authDisposition = .credential(credential)
        tab.navigationRuntime.lifecycleNavigationRuntime = lifecycle.runtime
        let responder = tab.makeMainFrameLifecycleResponder()
        let challenge = makeAuthenticationChallenge()

        let disposition = await responder.didReceive(challenge)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(lifecycle.authChallengeHosts, ["auth.example"])
        XCTAssertEqual(lifecycle.authTabIds, [tab.id])
        guard case .credential(let resolvedCredential)? = disposition else {
            return XCTFail("Expected credential disposition, got \(String(describing: disposition))")
        }
        XCTAssertEqual(resolvedCredential.user, credential.user)
        XCTAssertEqual(resolvedCredential.password, credential.password)
        XCTAssertEqual(resolvedCredential.persistence, credential.persistence)
    }

    func testTabLifecycleDestructiveCleanupSuppressionUsesInjectedRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabLifecycleNavigationRuntime()
        let extensionProperties = NavigationRecordingTabExtensionPropertiesRuntime()
        lifecycle.isPreparingForDestructiveCleanup = true
        tab.navigationRuntime.lifecycleNavigationRuntime = lifecycle.runtime
        tab.navigationRuntime.extensionPropertiesRuntime = extensionProperties.runtime
        let responder = tab.makeMainFrameLifecycleResponder()
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        let navigation = NSObject()

        responder.navigationDidFinish(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                action: nil,
                url: SumiSurface.emptyTabURL,
                isCurrent: true,
                isMainFrame: true,
                webView: webView
            )
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(lifecycle.cleanupCheckWebViewIds, [ObjectIdentifier(webView)])
        XCTAssertEqual(lifecycle.finishedCleanupWebViewIds, [ObjectIdentifier(webView)])
        XCTAssertTrue(extensionProperties.properties.isEmpty)
        XCTAssertTrue(lifecycle.zoomTabIds.isEmpty)
        XCTAssertTrue(lifecycle.siteDataPolicyTabIds.isEmpty)
    }

    func testTabLifecycleIgnoresNonCurrentSameDocumentNavigation() {
        let initialURL = URL(string: "https://example.com/page")!
        let sameDocumentURL = URL(string: "https://example.com/page#running")!
        let tab = Tab(url: initialURL)
        let responder = tab.makeMainFrameLifecycleResponder()
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = sameDocumentURL
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            targetURL: initialURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: nil
        ), .authority)

        responder.navigationDidSameDocumentNavigation(
            type: .sessionStatePop,
            context: SumiNavigationContext(
                navigationID: navigationID,
                navigationLifetime: navigation,
                action: nil,
                url: sameDocumentURL,
                isCurrent: false,
                isMainFrame: true,
                webView: webView
            )
        )

        XCTAssertEqual(tab.url, initialURL)

        responder.navigationDidSameDocumentNavigation(
            type: .anchorNavigation,
            context: SumiNavigationContext(
                navigationID: navigationID,
                navigationLifetime: navigation,
                action: nil,
                url: sameDocumentURL,
                isCurrent: true,
                isMainFrame: true,
                webView: webView
            )
        )

        XCTAssertEqual(tab.url, sameDocumentURL)
    }

    func testSumiNavigationResponseAdapterCopiesHTTPAndMainFrameNavigationMetadata() throws {
        let initialAction = navigationAction(
            url: URL(string: "https://example.com/start")!,
            navigationType: .linkActivated(isMiddleClick: false),
            requestCachePolicy: .returnCacheDataElseLoad
        )
        let finalAction = navigationAction(
            url: URL(string: "https://example.com/file.bin")!,
            navigationType: .custom(SumiCustomNavigationType.userRequestedPageDownload.navigationCustomNavigationType),
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
        XCTAssertFalse(try XCTUnwrap(value.isHTTPStatusSuccessful))
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

            XCTAssertEqual(policy, expectedPolicy.navigationActionPolicy)
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

            XCTAssertEqual(policy, expectedPolicy.navigationResponsePolicy)
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

            XCTAssertEqual(policy, expectedPolicy.navigationActionPolicy)
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

            XCTAssertEqual(policy, expectedPolicy.navigationResponsePolicy)
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

        XCTAssertEqual(responsePolicy, SumiNavigationResponsePolicy.download.navigationResponsePolicy)
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
        let weakTarget = WeakTestReference(target)
        let adapter = SumiNavigationResponderAdapter(target: target!)
        var preferences = NavigationPreferences.default

        target = nil

        XCTAssertNil(weakTarget.value)
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
        XCTAssertEqual(target.observedContexts.count, 1)
        XCTAssertNil(target.observedContexts.first ?? nil)
    }

    func testSumiNavigationResponderAdapterMapsNonAuthTargetToNext() async {
        let adapter = SumiNavigationResponderAdapter(target: NSObject())

        let disposition = await adapter.didReceive(makeAuthenticationChallenge(), for: nil)

        XCTAssertNil(disposition)
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

    func testSumiNavigationResponderAdapterPassesAuthNavigationContextWhenAvailable() async {
        let target = SumiNavigationAuthProbeResponder(decision: .next)
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/auth")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        _ = await adapter.didReceive(makeAuthenticationChallenge(), for: navigation)

        XCTAssertEqual(target.callCount, 1)
        XCTAssertEqual(target.observedContexts.count, 1)
        XCTAssertEqual(target.observedContexts.first??.url, URL(string: "https://example.com/auth")!)
        XCTAssertEqual(target.observedContexts.first??.isMainFrame, true)
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
                didSameDocumentNavigationOf: WKSameDocumentNavigationType(rawValue: type.rawValue)!
            )
        }

        XCTAssertEqual(target.observedTypes, SumiSameDocumentNavigationType.allCases)
    }

    func testSumiNavigationResponderAdapterPassesLifecycleNavigationContext() {
        let webView = WKWebView(frame: .zero)
        let target = SumiNavigationLifecycleContextProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(
            receiving: navigationAction(
                url: URL(string: "https://example.com/context")!,
                navigationType: .backForward(distance: -1),
                webView: webView
            ),
            isCurrent: true
        )
        let failure = WKError(.webContentProcessTerminated)

        adapter.willStart(navigation)
        adapter.didStart(navigation)
        adapter.didCommit(navigation)
        adapter.navigationDidFinish(navigation)
        adapter.navigation(navigation, didFailWith: failure)
        adapter.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePop)

        XCTAssertEqual(
            target.events,
            ["willStart", "didStart", "didCommit", "finish", "fail", "sameDocument.sessionStatePop"]
        )
        XCTAssertEqual(target.contexts.map { $0.url }, Array(repeating: URL(string: "https://example.com/context")!, count: 6))
        XCTAssertEqual(target.contexts.map { $0.isCurrent }, Array(repeating: true, count: 6))
        XCTAssertEqual(target.contexts.map { $0.isMainFrame }, Array(repeating: true, count: 6))
        XCTAssertEqual(target.contexts.map { $0.action?.navigationType.isBackForward }, Array(repeating: true, count: 6))
        XCTAssertTrue(target.contexts.allSatisfy { $0.webView === webView })
        XCTAssertEqual(target.failErrors.map(\.code), [.webContentProcessTerminated])
    }

    func testSumiNavigationResponderAdapterForwardsSameDocumentCallbacksInAdapterOrderAndIgnoresNonConformingTargets() {
        let recorder = SumiNavigationAdapterOrderRecorder()
        let first = SumiSameDocumentNavigationProbeResponder(name: "first", recorder: recorder)
        let nonSameDocument = SumiNavigationAdapterProbeResponder(name: "policy-only")
        let second = SumiSameDocumentNavigationProbeResponder(name: "second", recorder: recorder)
        let responders = [first, nonSameDocument, second].map(SumiNavigationResponderAdapter.init(target:))
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/page#push")!,
            navigationType: .sameDocumentNavigation(.sessionStatePush)
        ))

        for responder in responders {
            responder.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePush)
        }

        XCTAssertEqual(
            recorder.snapshot(),
            ["first.sameDocument.sessionStatePush", "second.sameDocument.sessionStatePush"]
        )
        XCTAssertEqual(first.observedTypes, [.sessionStatePush])
        XCTAssertEqual(second.observedTypes, [.sessionStatePush])
    }

    func testSumiNavigationResponderAdapterForwardsLifecycleStart() {
        let target = SumiNavigationStartProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/start")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        adapter.didStart(navigation)

        XCTAssertEqual(target.startCallCount, 1)
        XCTAssertEqual(target.startContexts.first?.url, URL(string: "https://example.com/start")!)
    }

    func testSumiNavigationResponderAdapterForwardsLifecycleStartInAdapterOrderAndIgnoresNonConformingTargets() {
        let recorder = SumiNavigationAdapterOrderRecorder()
        let first = SumiNavigationStartProbeResponder(name: "first", recorder: recorder)
        let nonStart = SumiNavigationAdapterProbeResponder(name: "policy-only")
        let second = SumiNavigationStartProbeResponder(name: "second", recorder: recorder)
        let responders = [first, nonStart, second].map(SumiNavigationResponderAdapter.init(target:))
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/ordered-start")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        for responder in responders {
            responder.didStart(navigation)
        }

        XCTAssertEqual(recorder.snapshot(), ["first.start", "second.start"])
        XCTAssertEqual(first.startCallCount, 1)
        XCTAssertEqual(second.startCallCount, 1)
    }

    func testWeakSumiNavigationStartAdapterIgnoresDeallocatedTarget() {
        var target: SumiNavigationStartProbeResponder? = SumiNavigationStartProbeResponder()
        let weakTarget = WeakTestReference(target)
        let adapter = SumiNavigationResponderAdapter(target: target!)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/deallocated-start")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        target = nil

        XCTAssertNil(weakTarget.value)
        adapter.didStart(navigation)
    }

    func testFindInPageResponderClosesOnSumiNavigationStart() {
        let findInPage = FindInPageTabExtension()
        findInPage.model.show()

        findInPage.navigationDidStart()

        XCTAssertFalse(findInPage.model.isVisible)
    }

    func testFindInPageResponderClosesOnlyForSumiPushAndPopSameDocumentNavigation() {
        let findInPage = FindInPageTabExtension()

        findInPage.model.show()
        findInPage.navigationDidSameDocumentNavigation(type: .anchorNavigation)
        XCTAssertTrue(findInPage.model.isVisible)

        findInPage.navigationDidSameDocumentNavigation(type: .sessionStateReplace)
        XCTAssertTrue(findInPage.model.isVisible)

        findInPage.navigationDidSameDocumentNavigation(type: .sessionStatePush)
        XCTAssertFalse(findInPage.model.isVisible)

        findInPage.model.show()
        findInPage.navigationDidSameDocumentNavigation(type: .sessionStatePop)
        XCTAssertFalse(findInPage.model.isVisible)
    }

    func testWeakFindInPageAdapterDoesNotRetainTarget() {
        var findInPage: FindInPageTabExtension? = FindInPageTabExtension()
        let weakFindInPage = WeakTestReference(findInPage)
        let adapter = SumiNavigationResponderAdapter(target: findInPage!)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/deallocated-find")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        findInPage = nil

        XCTAssertNil(weakFindInPage.value)
        adapter.didStart(navigation)
        adapter.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePush)
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
        XCTAssertEqual(first.finishContexts.first?.url, URL(string: "https://example.com/completion")!)
        XCTAssertEqual(first.failContexts.first?.url, URL(string: "https://example.com/completion")!)
        XCTAssertEqual(first.failErrors.map(\.code), [.unknown])
    }

    func testWeakSumiNavigationCompletionAdapterIgnoresDeallocatedTarget() {
        let recorder = SumiNavigationAdapterOrderRecorder()
        var target: SumiNavigationCompletionProbeResponder? = SumiNavigationCompletionProbeResponder(
            name: "temporary",
            recorder: recorder
        )
        let weakTarget = WeakTestReference(target)
        let adapter = SumiNavigationResponderAdapter(target: target!)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/deallocated-completion")!,
            navigationType: .linkActivated(isMiddleClick: false)
        ))

        target = nil

        XCTAssertNil(weakTarget.value)
        adapter.navigationDidFinish(navigation)
        adapter.navigation(navigation, didFailWith: WKError(.unknown))
        XCTAssertEqual(recorder.snapshot(), [])
    }

    func testSumiNavigationAdapterTerminatesCancelledExpectedMainFrameAction() {
        let webView = WKWebView(frame: .zero)
        let target = SumiNavigationTerminalProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://example.com/cancelled")!,
            navigationType: .other,
            webView: webView
        ))

        adapter.didCancelNavigationAction(
            navigation.navigationAction,
            withRedirectNavigations: nil
        )

        XCTAssertEqual(target.terminations.count, 1)
        XCTAssertEqual(
            target.terminations.first?.navigationID,
            ObjectIdentifier(navigation)
        )
        XCTAssertIdentical(target.terminations.first?.webView, webView)
        XCTAssertEqual(target.terminations.first?.reason, .actionCancelled)
    }

    func testSumiNavigationAdapterRoutesProcessTerminationToInstalledWebView() {
        let webView = WKWebView(frame: .zero)
        let target = SumiNavigationTerminalProbeResponder()
        let adapter = SumiNavigationResponderAdapter(target: target)
        adapter.bind(to: webView)

        adapter.webContentProcessDidTerminate(with: nil)

        XCTAssertEqual(target.terminatedWebViews.count, 1)
        XCTAssertIdentical(target.terminatedWebViews.first, webView)
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
        XCTAssertIdentical(controller.normalTabUserScriptsProvider, scriptsProvider)

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
                sourceWebView: WKWebView(frame: .zero),
                targetWebView: webView
            ),
            preferences: &preferences
        )

        XCTAssertActionPolicy(policy, .allow)
        XCTAssertEqual(scriptsProvider.scriptsRevision, 1)
        XCTAssertEqual(observer.observedScriptRevisions, [1])
    }

}
