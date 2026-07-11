import Foundation
import SumiDomain
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class TabScriptMessageHandlerIsolationTests: XCTestCase {
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

        try await postContextMenuTarget(
            kind: .link,
            selectedText: "first selection",
            context: try contextMenuContext(in: firstWebView),
            in: firstWebView
        )
        let receivedFirstTarget = try await waitForContextMenuTarget(.link, on: firstWebView)
        let firstTarget = try XCTUnwrap(receivedFirstTarget)
        XCTAssertEqual(firstTarget.selectedText, "first selection")
        XCTAssertNil(secondWebView.contextMenu.recentTarget())

        try await postContextMenuTarget(
            kind: .editable,
            selectedText: "second selection",
            context: try contextMenuContext(in: secondWebView),
            in: secondWebView
        )
        let receivedSecondTarget = try await waitForContextMenuTarget(.editable, on: secondWebView)
        let secondTarget = try XCTUnwrap(receivedSecondTarget)
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
        let webView = FocusableWKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.owningTab = tab

        await normalTabController.waitForContentBlockingAssetsInstalled()
        await loadBlankDocument(into: webView)

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

        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(false);",
            in: webView
        )
        try await waitForSuspensionDecision(
            .vetoed(.pageReportedUnableToSuspend),
            on: tab
        )
        XCTAssertEqual(evidenceChangeCount, 2)

        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(true);",
            in: webView
        )
        try await waitForSuspensionDecision(.allowed, on: tab)
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

        try await postTabSuspensionCanBeSuspended(
            false,
            in: secondWebView
        )

        try await waitForSuspensionDecision(
            .vetoed(.pageReportedUnableToSuspend),
            on: secondTab
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

        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(tabSuspensionContext(for: tab))"];
            handler.postMessage({
                context: "\(tabSuspensionContext(for: tab))",
                featureName: "tabSuspension",
                method: "canBeSuspended",
                params: { canBeSuspended: "false" }
            });
            handler.postMessage({
                context: "\(tabSuspensionContext(for: tab))",
                featureName: "tabSuspension",
                method: "unknownMethod",
                params: { canBeSuspended: false }
            });
            handler.postMessage({
                context: "\(tabSuspensionContext(for: tab))",
                featureName: "unknownFeature",
                method: "canBeSuspended",
                params: { canBeSuspended: false }
            });
            """,
            in: webView
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
    }

    func testSubframeCannotPublishMainDocumentSuspensionEvidence() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Subframe Suspension",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)
        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(true);",
            in: webView
        )
        try await waitForSuspensionDecision(.allowed, on: tab)

        let context = tabSuspensionContext(for: tab)
        _ = try await webView.callAsyncJavaScript(
            """
            return await new Promise(resolve => {
                const frame = document.createElement("iframe");
                frame.srcdoc = "<!doctype html><body>frame</body>";
                frame.onload = () => {
                    frame.contentWindow.webkit?.messageHandlers?.[context]
                        ?.postMessage({
                            context,
                            method: "pageState",
                            params: {
                                documentIdentity: "forged-subframe",
                                sequence: 1000,
                                canBeSuspended: false
                            }
                        });
                    resolve(true);
                };
                document.body.appendChild(frame);
            });
            """,
            arguments: ["context": context],
            in: nil,
            contentWorld: .page
        )
        try await Task.sleep(nanoseconds: 100_000_000)

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
        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(true);",
            in: trackedWebView
        )
        try await waitForSuspensionDecision(.allowed, on: tab)

        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(false);",
            in: untrackedWebView
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(tab.committedDocumentRuntime.suspensionDecision, .allowed)
    }

    func testPictureInPictureInsideIframeVetoesPhysicalDocument() async throws {
        let transaction = TabMainFrameRuntimeTransaction(initialURL: SumiSurface.emptyTabURL)
        let tab = Tab(
            name: "Iframe PiP",
            mainFrameRuntimeTransaction: transaction
        )
        let webView = try await makeWebView(with: tab, transaction: transaction)

        try await evaluate(
            """
            const frame = document.createElement("iframe");
            frame.id = "pip-frame";
            frame.srcdoc = `<!doctype html><body><script>
                const video = document.createElement("video");
                document.body.appendChild(video);
                setTimeout(() => {
                    video.dispatchEvent(new Event("play"));
                    setTimeout(() => {
                        video.dispatchEvent(
                            new Event("enterpictureinpicture")
                        );
                    }, 250);
                }, 0);
            </script></body>`;
            document.body.appendChild(frame);
            """,
            in: webView
        )
        try await waitForSuspensionDecision(
            .vetoed(.pictureInPicture),
            on: tab
        )

        try await evaluate(
            """
            const frame = document.getElementById("pip-frame");
            frame?.contentDocument?.querySelector("video")?.dispatchEvent(
                new frame.contentWindow.Event("leavepictureinpicture")
            );
            frame?.remove();
            """,
            in: webView
        )
        try await waitForSuspensionDecision(.allowed, on: tab)
    }

    private func linkContext(for tab: Tab) -> String {
        "sumiLinkInteraction_\(tab.id.uuidString)"
    }

    private func tabSuspensionContext(for tab: Tab) -> String {
        "sumiTabSuspension_\(tab.id.uuidString)"
    }

    private func scriptShapes(_ scripts: [SumiUserScript]) -> [ScriptShape] {
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
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: tab.normalTabCoreUserScripts()
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.owningTab = tab
        await normalTabController.waitForContentBlockingAssetsInstalled()
        await loadBlankDocument(into: webView)
        if establishDocument {
            establishCommittedDocument(
                on: webView,
                for: tab,
                transaction: transaction
            )
            try await waitForSuspensionDecision(.allowed, on: tab)
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
    ) async throws {
        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (handler) {
                handler.postMessage({
                    kind: "\(kind.rawValue)",
                    selectedText: "\(selectedText)"
                });
            }
            """,
            in: webView,
            contentWorld: .defaultClient
        )
    }

    private func waitForContextMenuTarget(
        _ kind: SumiWebPageContextMenuTargetKind,
        on webView: FocusableWKWebView
    ) async throws -> SumiWebPageContextMenuTargetSnapshot? {
        for _ in 0..<100 {
            if let target = webView.contextMenu.recentTarget(), target.kind == kind {
                return target
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func postTabSuspensionCanBeSuspended(
        _ canBeSuspended: Bool,
        in webView: WKWebView
    ) async throws {
        try await evaluate(
            "window.__sumiTabSuspension.canBeSuspended(\(canBeSuspended ? "true" : "false"));",
            in: webView
        )
    }

    private func waitForSuspensionDecision(
        _ expected: TabDocumentSuspensionDecision,
        on tab: Tab,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<100 {
            if tab.committedDocumentRuntime.suspensionDecision == expected {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(
            tab.committedDocumentRuntime.suspensionDecision,
            expected,
            file: file,
            line: line
        )
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
            committedURL: url
        ) else {
            return XCTFail("Expected script-message document authority to publish")
        }
        withExtendedLifetime(navigation) {}
    }

    private func loadBlankDocument(into webView: WKWebView) async {
        let didFinish = expectation(description: "blank document loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            "<!doctype html><html><body>ok</body></html>",
            baseURL: URL(string: "https://example.com")
        )

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
