import AppKit
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

    func testDelegateTeardownCancelsPendingActionDecisionExactlyOnce() {
        let proxy = CountingNavigationDelegateProxy()
        let started = expectation(description: "action decision started")
        let completed = expectation(description: "action decision completed")
        let responder = SuspendedActionPolicyResponder(onStart: {
            started.fulfill()
        })
        let webView = WKWebView(frame: .zero)
        proxy.onActionDecision = { policy in
            XCTAssertEqual(policy, .cancel)
            completed.fulfill()
        }
        proxy.distributedNavigationDelegate.setResponders(.strong(responder))
        webView.navigationDelegate = proxy

        webView.load(URLRequest(url: URL(string: "https://example.com/held")!))
        wait(for: [started], timeout: 5)
        proxy.distributedNavigationDelegate.cancelPendingNavigationDecisions()
        wait(for: [completed], timeout: 1)
        responder.resume(with: .allow)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(proxy.actionDecisionCount, 1)
    }

    func testDelegateTeardownCancelsPendingAuthenticationDecisionExactlyOnce() {
        let delegate = DistributedNavigationDelegate()
        let started = expectation(description: "authentication decision started")
        let completed = expectation(description: "authentication decision completed")
        let responder = SuspendedAuthenticationResponder(onStart: {
            started.fulfill()
        })
        let webView = WKWebView(frame: .zero)
        var completionCount = 0
        delegate.setResponders(.strong(responder))

        delegate.webView(
            webView,
            didReceive: makeAuthenticationChallenge()
        ) { disposition, credential in
            completionCount += 1
            XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            XCTAssertNil(credential)
            completed.fulfill()
        }
        wait(for: [started], timeout: 1)
        delegate.cancelPendingNavigationDecisions()
        wait(for: [completed], timeout: 1)
        responder.resume(with: .cancel)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(completionCount, 1)
    }

    func testDelegateTeardownCancelsPendingResponseDecisionExactlyOnce() {
        let proxy = CountingNavigationDelegateProxy()
        let started = expectation(description: "response decision started")
        let completed = expectation(description: "response decision completed")
        let responder = SuspendedResponsePolicyResponder(onStart: {
            started.fulfill()
        })
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            RespondingSchemeHandler(),
            forURLScheme: RespondingSchemeHandler.scheme
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        proxy.onResponseDecision = { policy in
            XCTAssertEqual(policy, .cancel)
            completed.fulfill()
        }
        proxy.distributedNavigationDelegate.setResponders(.strong(responder))
        webView.navigationDelegate = proxy

        webView.load(URLRequest(
            url: URL(string: "\(RespondingSchemeHandler.scheme)://example/document")!
        ))
        wait(for: [started], timeout: 5)
        proxy.distributedNavigationDelegate.cancelPendingNavigationDecisions()
        wait(for: [completed], timeout: 1)
        responder.resumeAllow()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(proxy.responseDecisionCount, 1)
    }

    func testActionDecisionCompletesBeforeLifecycleSideEffectBegins() {
        let proxy = CountingNavigationDelegateProxy()
        let responder = LifecycleOrderingProbeResponder()
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
            downloadManager: { nil },
            downloadTransportFactory: { nil }
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

    func testSumiNavigationActionAdapterTreatsReleasedFrameOwnersAsNewWindow() {
        let url = URL(string: "https://released-frame.example/page")!
        let origin = SumiSecurityOrigin(
            protocol: "https",
            host: "released-frame.example",
            port: 0
        )
        var sourceFrame = origin.navigationFrameInfo(
            webView: WKWebView(frame: .zero),
            handle: FrameHandle(rawValue: UInt64(11))!,
            isMainFrame: true,
            url: url
        )
        var targetFrame = origin.navigationFrameInfo(
            webView: WKWebView(frame: .zero),
            handle: FrameHandle(rawValue: UInt64(12))!,
            isMainFrame: true,
            url: url
        )
        sourceFrame.webView = nil
        targetFrame.webView = nil
        let action = NavigationAction(
            request: URLRequest(url: url),
            navigationType: .other,
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: false,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        let sumiAction = SumiNavigationAction(action)

        XCTAssertTrue(sumiAction.isTargetingNewWindow)
        XCTAssertEqual(sumiAction.sourceFrame?.handle?.frameID, 11)
        XCTAssertEqual(sumiAction.targetFrame?.handle?.frameID, 12)
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
        try installTestProfile(profile, in: harness.container)
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
        try installTestProfile(profileA, in: harness.container)
        try installTestProfile(profileB, in: harness.container)
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

}
