import Foundation
@testable import Sumi
import SumiDomain
import WebKit
import XCTest

@MainActor
final class TabScriptMessageHandlerIsolationTests: XCTestCase {
    private var defaultsHarness: TestDefaultsHarness!
    private var settings: SumiSettingsService!
    private var pageServer: AutofillPagesHTTPServer?

    override func setUp() {
        super.setUp()
        defaultsHarness = TestDefaultsHarness()
        settings = SumiSettingsService(userDefaults: defaultsHarness.defaults)
        settings.memoryMode = .balanced
    }

    override func tearDown() {
        pageServer?.stop()
        pageServer = nil
        settings = nil
        defaultsHarness.reset()
        defaultsHarness = nil
        super.tearDown()
    }

    private struct ScriptShape: Equatable {
        let typeName: String
        let injectionTime: WKUserScriptInjectionTime
        let forMainFrameOnly: Bool
        let requiresRunInPageContentWorld: Bool
    }

    func testNormalTabCoreScriptFacadeBuildsCanonicalScriptSet() {
        let tab = Tab(name: "Core Scripts")

        XCTAssertEqual(
            scriptShapes(tab.normalTabCoreUserScripts()),
            scriptShapes(makeNormalTabCoreUserScripts(for: tab))
        )
    }

    func testLinkHoverMessagesRemainScopedToPhysicalWebViewClones() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Cloned",
            mainFrameRuntimeTransaction: transaction
        )
        let firstWebView = try await makeWebView(with: tab, transaction: transaction)
        let secondWebView = try await makeWebView(with: tab, transaction: transaction)
        let firstDelivered = expectation(description: "first physical WebView delivered")
        let secondDelivered = expectation(description: "second physical WebView delivered")
        let firstObservation = firstWebView.hoveredLink.observe { href in
            if href == "https://first.example/" {
                firstDelivered.fulfill()
            }
        }
        let secondObservation = secondWebView.hoveredLink.observe { href in
            if href == "https://second.example/" {
                secondDelivered.fulfill()
            }
        }

        try await postLinkHover(
            "https://first.example/",
            context: linkContext(for: tab),
            in: firstWebView
        )
        await fulfillment(of: [firstDelivered], timeout: 5.0)
        XCTAssertEqual(firstWebView.hoveredLink.href, "https://first.example/")
        XCTAssertNil(secondWebView.hoveredLink.href)

        try await postLinkHover(
            "https://second.example/",
            context: linkContext(for: tab),
            in: secondWebView
        )
        await fulfillment(of: [secondDelivered], timeout: 5.0)

        XCTAssertEqual(firstWebView.hoveredLink.href, "https://first.example/")
        XCTAssertEqual(secondWebView.hoveredLink.href, "https://second.example/")
        withExtendedLifetime((firstObservation, secondObservation)) {}
    }

    func testContextMenuMessagesRemainScopedToPhysicalWebViewClones() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Context Clones",
            mainFrameRuntimeTransaction: transaction
        )
        let firstWebView = try await makeWebView(with: tab, transaction: transaction)
        let secondWebView = try await makeWebView(with: tab, transaction: transaction)

        let firstAccepted = try await postContextMenuTarget(
            kind: .link,
            selectedText: "first selection",
            context: try contextMenuContext(in: firstWebView),
            in: firstWebView
        )
        XCTAssertTrue(firstAccepted)
        let firstTarget = try XCTUnwrap(firstWebView.contextMenu.recentTarget())
        XCTAssertEqual(firstTarget.selectedText, "first selection")
        XCTAssertNil(secondWebView.contextMenu.recentTarget())

        let secondAccepted = try await postContextMenuTarget(
            kind: .editable,
            selectedText: "second selection",
            context: try contextMenuContext(in: secondWebView),
            in: secondWebView
        )
        XCTAssertTrue(secondAccepted)
        let secondTarget = try XCTUnwrap(secondWebView.contextMenu.recentTarget())
        XCTAssertEqual(secondTarget.selectedText, "second selection")
        XCTAssertEqual(firstWebView.contextMenu.recentTarget()?.kind, .link)
    }

    func testControllerCleanupRemovesBrokerHandlers() async throws {
        let tab = Tab(name: "Cleanup")
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: tab.normalTabCoreUserScripts()
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let webView = FocusableWKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.owningTab = tab

        await normalTabController.waitForContentBlockingAssetsInstalled()
        try await loadBlankDocument(into: webView)

        normalTabController.cleanUpBeforeClosing()

        let removedHandlerDidNotFire = expectation(description: "removed handler stays detached")
        removedHandlerDidNotFire.isInverted = true
        let observation = webView.hoveredLink.observe { _ in
            removedHandlerDidNotFire.fulfill()
        }

        try await postLinkHover(
            "https://removed.example/",
            context: linkContext(for: tab),
            in: webView
        )

        await fulfillment(of: [removedHandlerDidNotFire], timeout: 0.5)
        XCTAssertNil(webView.hoveredLink.href)
        withExtendedLifetime(observation) {}
    }

    func testMalformedLinkHoverPayloadFailsLocally() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Malformed",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)
        let malformedDidNotFire = expectation(description: "malformed payload has no side effects")
        malformedDidNotFire.isInverted = true
        let observation = webView.hoveredLink.observe { _ in
            malformedDidNotFire.fulfill()
        }

        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(linkContext(for: tab))"];
            handler.postMessage({
                context: "\(linkContext(for: tab))",
                featureName: "linkInteraction",
                method: "linkHover",
                params: []
            });
            """,
            in: webView,
            contentWorld: .defaultClient
        )

        await fulfillment(of: [malformedDidNotFire], timeout: 0.5)
        XCTAssertNil(webView.hoveredLink.href)
        withExtendedLifetime(observation) {}
    }

    func testUnknownLinkHoverMethodIsIgnoredSafely() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Unknown",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)
        let unknownDidNotFire = expectation(description: "unknown message has no side effects")
        unknownDidNotFire.isInverted = true
        let observation = webView.hoveredLink.observe { _ in
            unknownDidNotFire.fulfill()
        }

        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(linkContext(for: tab))"];
            handler.postMessage({
                context: "\(linkContext(for: tab))",
                featureName: "linkInteraction",
                method: "unknownMethod",
                params: {}
            });
            """,
            in: webView,
            contentWorld: .defaultClient
        )

        await fulfillment(of: [unknownDidNotFire], timeout: 0.5)
        XCTAssertNil(webView.hoveredLink.href)
        withExtendedLifetime(observation) {}
    }

    func testTabSuspensionPageAPIUpdatesPageVetoState() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Suspension",
            mainFrameRuntimeTransaction: transaction
        )
        var evidenceChangeCount = 0
        tab.navigationRuntime.lifecycleNavigationRuntime
            .reconcileDocumentSuspensionState = { _ in
                evidenceChangeCount += 1
            }
        let webView = try await makeWebView(with: tab, transaction: transaction)
        XCTAssertEqual(evidenceChangeCount, 1)

        let vetoAccepted = try await postTabSuspensionCanBeSuspended(false, in: webView)
        XCTAssertTrue(vetoAccepted)
        XCTAssertEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pageReportedUnableToSuspend)
        )
        XCTAssertEqual(evidenceChangeCount, 2)

        let allowAccepted = try await postTabSuspensionCanBeSuspended(true, in: webView)
        XCTAssertTrue(allowAccepted)
        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
        XCTAssertEqual(evidenceChangeCount, 3)
    }

    func testTabSuspensionMessagesRemainScopedByContext() async throws {
        let firstTransaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let firstTab = Tab(
            name: "First Suspension",
            mainFrameRuntimeTransaction: firstTransaction
        )
        let secondTransaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let secondTab = Tab(
            name: "Second Suspension",
            mainFrameRuntimeTransaction: secondTransaction
        )
        let firstWebView = try await makeWebView(
            with: firstTab,
            transaction: firstTransaction
        )
        let secondWebView = try await makeWebView(
            with: secondTab,
            transaction: secondTransaction
        )

        let secondAccepted = try await postTabSuspensionCanBeSuspended(
            false,
            in: secondWebView
        )
        XCTAssertTrue(secondAccepted)
        XCTAssertEqual(
            secondTab.committedDocumentRuntime.suspensionDecision,
            .vetoed(.pageReportedUnableToSuspend)
        )
        XCTAssertEqual(
            firstTab.committedDocumentRuntime.suspensionDecision,
            .allowed
        )
        withExtendedLifetime(firstWebView) {}
    }

    func testMalformedAndIrrelevantTabSuspensionMessagesAreIgnoredSafely() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Malformed Suspension",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)

        let allMessagesWereRejected = try await webView.callAsyncJavaScript(
            """
            const handler = window.webkit?.messageHandlers?.["\(tabSuspensionContext(for: tab))"];
            if (!handler) { throw new Error("tab suspension handler missing"); }
            const replies = await Promise.all([
                handler.postMessage({
                    context: "\(tabSuspensionContext(for: tab))",
                    featureName: "tabSuspension",
                    method: "canBeSuspended",
                    params: { canBeSuspended: "false" }
                }),
                handler.postMessage({
                    context: "\(tabSuspensionContext(for: tab))",
                    featureName: "tabSuspension",
                    method: "unknownMethod",
                    params: { canBeSuspended: false }
                }),
                handler.postMessage({
                    context: "\(tabSuspensionContext(for: tab))",
                    featureName: "unknownFeature",
                    method: "canBeSuspended",
                    params: { canBeSuspended: false }
                })
            ]);
            return replies.every(reply => reply?.accepted === false);
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool

        XCTAssertEqual(allMessagesWereRejected, true)
        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
    }

    func testSubframeCannotPublishMainDocumentSuspensionEvidence() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Subframe Suspension",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)
        let canonicalAccepted = try await postTabSuspensionCanBeSuspended(true, in: webView)
        XCTAssertTrue(canonicalAccepted)

        let context = tabSuspensionContext(for: tab)
        let reply = try await webView.callAsyncJavaScript(
            """
            return await new Promise((resolve, reject) => {
                const frame = document.createElement("iframe");
                frame.srcdoc = "<!doctype html><body>frame</body>";
                frame.onload = async () => {
                    const handler = frame.contentWindow.webkit?.messageHandlers?.[context];
                    if (!handler) {
                        reject(new Error("subframe tab suspension handler missing"));
                        return;
                    }
                    try {
                        resolve(await handler.postMessage({
                            context,
                            method: "pageState",
                            params: {
                                documentIdentity: "forged-subframe",
                                sequence: 1000,
                                canBeSuspended: false
                            }
                        }));
                    } catch (error) {
                        reject(error);
                    }
                };
                document.body.appendChild(frame);
            });
            """,
            arguments: ["context": context],
            in: nil,
            contentWorld: .page
        )

        XCTAssertFalse(try acceptedReply(from: reply))
        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
    }

    func testUntrackedWebViewCannotOverwriteCanonicalReplicaReport() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Untracked Suspension",
            mainFrameRuntimeTransaction: transaction
        )
        let trackedWebView = try await makeWebView(with: tab, transaction: transaction)
        let untrackedWebView = try await makeWebView(
            with: tab,
            transaction: transaction,
            establishDocument: false
        )
        let trackedAccepted = try await postTabSuspensionCanBeSuspended(true, in: trackedWebView)
        XCTAssertTrue(trackedAccepted)

        let untrackedAccepted = try await postTabSuspensionCanBeSuspended(
            false,
            in: untrackedWebView
        )
        XCTAssertFalse(untrackedAccepted)

        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
    }

    private func linkContext(for _: Tab) -> String {
        "sumiLinkInteraction"
    }

    private func tabSuspensionContext(for _: Tab) -> String {
        "sumiTabSuspension"
    }

    private func scriptShapes(_ scripts: [SumiPageScript]) -> [ScriptShape] {
        scripts.map { script in
            ScriptShape(
                typeName: String(describing: type(of: script)),
                injectionTime: script.injectionTime,
                forMainFrameOnly: script.forMainFrameOnly,
                requiresRunInPageContentWorld: script.requiresRunInPageContentWorld
            )
        }
    }

    private func makeWebView(
        with tab: Tab,
        transaction: TabMainFrameRuntimeTransaction,
        establishDocument: Bool = true
    ) async throws -> FocusableWKWebView {
        tab.sumiSettings = settings
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: tab.normalTabCoreUserScripts()
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let webView = FocusableWKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.owningTab = tab
        await normalTabController.waitForContentBlockingAssetsInstalled()
        try await loadBlankDocument(into: webView)
        if establishDocument {
            establishCommittedDocument(
                on: webView,
                for: tab,
                transaction: transaction
            )
            let initialEvidenceAccepted = await waitForTabSuspensionActivation(
                in: webView
            )
            XCTAssertTrue(initialEvidenceAccepted)
            XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
        }
        return webView
    }

    private func postLinkHover(_ href: String, context: String, in webView: WKWebView) async throws {
        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (handler) {
                handler.postMessage({
                    context: "\(context)",
                    featureName: "linkInteraction",
                    method: "linkHover",
                    params: { href: "\(href)" }
                });
            }
            """,
            in: webView,
            contentWorld: .defaultClient
        )
    }

    private func contextMenuContext(in webView: WKWebView) throws -> String {
        let provider = try XCTUnwrap(
            webView.configuration.userContentController.sumiNormalTabUserScriptsProvider
        )
        let script = try XCTUnwrap(provider.userScripts.first {
            $0.source.contains("__sumiWebPageContextMenuInstalled")
        })
        return try XCTUnwrap(script.messageNames.first)
    }

    private func postContextMenuTarget(
        kind: SumiWebPageContextMenuTargetKind,
        selectedText: String,
        context: String,
        in webView: WKWebView
    ) async throws -> Bool {
        let reply = try await webView.callAsyncJavaScript(
            """
            const handler = window.webkit?.messageHandlers?.[context];
            if (!handler) { throw new Error("context menu handler missing"); }
            return await handler.postMessage({ kind, selectedText });
            """,
            arguments: [
                "context": context,
                "kind": kind.rawValue,
                "selectedText": selectedText,
            ],
            in: nil,
            contentWorld: .defaultClient
        )
        return try acceptedReply(from: reply)
    }

    private func postTabSuspensionCanBeSuspended(
        _ canBeSuspended: Bool,
        in webView: WKWebView
    ) async throws -> Bool {
        let reply = try await webView.callAsyncJavaScript(
            """
            const suspension = window.__sumiTabSuspension;
            if (!suspension) { throw new Error("tab suspension API missing"); }
            return await suspension.canBeSuspended(canBeSuspended);
            """,
            arguments: ["canBeSuspended": canBeSuspended],
            in: nil,
            contentWorld: .page
        )
        return try acceptedReply(from: reply)
    }

    private func acceptedReply(
        from value: Any?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Bool {
        let dictionary = try XCTUnwrap(
            value as? [String: Any],
            file: file,
            line: line
        )
        return try XCTUnwrap(
            dictionary["accepted"] as? Bool,
            file: file,
            line: line
        )
    }

    private func waitForTabSuspensionActivation(
        in webView: WKWebView
    ) async -> Bool {
        for _ in 0..<100 {
            if (try? await postTabSuspensionCanBeSuspended(
                true,
                in: webView
            )) == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func establishCommittedDocument(
        on webView: WKWebView,
        for tab: Tab,
        transaction: TabMainFrameRuntimeTransaction
    ) {
        let url = webView.url ?? URL(string: "about:blank")!
        _ = tab.beginMainFrameNavigationIntent(to: url)
        guard let submission = tab.mainFrameLoads.claimDirectSubmission(on: webView) else {
            return XCTFail("Expected a physical main-frame submission lease")
        }
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            committedURL: url
        ) else {
            return XCTFail("Expected script-message document authority to publish")
        }
        withExtendedLifetime(navigation) {}
    }

    private func loadBlankDocument(into webView: WKWebView) async throws {
        let didFinish = expectation(description: "blank document loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }
        let server: AutofillPagesHTTPServer
        if let pageServer {
            server = pageServer
        } else {
            server = try await AutofillPagesHTTPServer.start(preferredPort: 0)
            pageServer = server
        }

        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: server.loginBasicURL))

        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
    }

    private func evaluate(
        _ script: String,
        in webView: WKWebView,
        contentWorld: WKContentWorld = .page
    ) async throws {
        let wrappedScript = """
        (() => {
        \(script)
        return null;
        })();
        """

        _ = try await webView.evaluateJavaScript(
            wrappedScript,
            in: nil,
            contentWorld: contentWorld
        )
    }
}

private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        _ = navigation
        onFinish()
    }
}
