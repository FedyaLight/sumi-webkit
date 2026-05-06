import Combine
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiNormalTabUserContentControllerParityTests: XCTestCase {
    func testNormalTabFactoryExposesSumiBoundaryAndInstallsProviderScriptsOnce() async throws {
        let provider = SumiNormalTabUserScripts(
            contentBlockingUserScripts: [
                ParityUserScript(context: "sumiParityContentBlocking", sourceMarker: "__sumiParityContentBlocking")
            ],
            managedUserScripts: [
                ParityUserScript(context: "sumiParityManaged", sourceMarker: "__sumiParityManaged")
            ]
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.sumiUsesNormalTabSumiUserContentController)
        XCTAssertTrue(normalTabController.wkUserContentController === controller)
        XCTAssertTrue(normalTabController.normalTabUserScriptsProvider === provider)
        XCTAssertTrue(controller.sumiNormalTabUserScriptsProvider === provider)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertFalse(normalTabController.contentBlockingAssetSummary.isContentBlockingFeatureEnabled)
        XCTAssertEqual(controller.userScripts.count, provider.userScripts.count)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityContentBlocking", in: controller), 1)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityManaged", in: controller), 1)
        XCTAssertEqual(installedScriptCount(containing: "__sumiDDGFaviconTransportInstalled", in: controller), 1)
    }

    func testReplacingManagedScriptsUpdatesVisibleInstalledSetAndKeepsProviderBoundary() async throws {
        let provider = SumiNormalTabUserScripts(
            contentBlockingUserScripts: [
                ParityUserScript(context: "sumiParityStableContentBlocking", sourceMarker: "__sumiParityStableContentBlocking")
            ],
            managedUserScripts: [
                ParityUserScript(context: "sumiParityFirstManaged", sourceMarker: "__sumiParityFirstManaged")
            ]
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        let initialSummary = normalTabController.contentBlockingAssetSummary

        provider.replaceManagedUserScripts([
            ParityUserScript(context: "sumiParitySecondManaged", sourceMarker: "__sumiParitySecondManaged")
        ])
        await normalTabController.replaceNormalTabUserScripts(with: provider)

        XCTAssertTrue(controller.sumiUsesNormalTabSumiUserContentController)
        XCTAssertTrue(normalTabController.normalTabUserScriptsProvider === provider)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary, initialSummary)
        XCTAssertEqual(controller.userScripts.count, provider.userScripts.count)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityStableContentBlocking", in: controller), 1)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityFirstManaged", in: controller), 0)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParitySecondManaged", in: controller), 1)
        XCTAssertEqual(installedScriptCount(containing: "__sumiDDGFaviconTransportInstalled", in: controller), 1)
    }

    func testEquivalentReplacementDoesNotDuplicateInstalledScripts() async throws {
        let provider = SumiNormalTabUserScripts(
            managedUserScripts: [
                ParityUserScript(context: "sumiParityIdempotentManaged", sourceMarker: "__sumiParityIdempotentManaged")
            ]
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        await normalTabController.replaceNormalTabUserScripts(with: provider)
        await normalTabController.replaceNormalTabUserScripts(with: provider)

        XCTAssertEqual(controller.userScripts.count, provider.userScripts.count)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityIdempotentManaged", in: controller), 1)
        XCTAssertEqual(installedScriptCount(containing: "__sumiDDGFaviconTransportInstalled", in: controller), 1)
    }

    func testWaitForContentBlockingAssetsInstalledReturnsForAlreadyInstalledDisabledAssets() async throws {
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController()
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()
        let installedSummary = normalTabController.contentBlockingAssetSummary
        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertTrue(installedSummary.isInstalled)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary, installedSummary)
        XCTAssertEqual(installedSummary.globalRuleListCount, 0)
        XCTAssertFalse(installedSummary.isContentBlockingFeatureEnabled)
    }

    func testDisabledNoAssetsAwaitKeepsVisibleSummaryEmptyAndDisabled() async throws {
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController()
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(
            normalTabController.contentBlockingAssetSummary,
            SumiNormalTabContentBlockingAssetSummary(
                isInstalled: true,
                globalRuleListCount: 0,
                updateRuleCount: 0,
                isContentBlockingFeatureEnabled: false
            )
        )
    }

    func testEnabledContentBlockingAssetsReportInstalledRuleAndFeatureSummary() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                Self.validRuleListDefinition(name: "SumiParityEnabledRules")
            ])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()
        let summary = normalTabController.contentBlockingAssetSummary

        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 1)
        XCTAssertEqual(summary.updateRuleCount, 1)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
    }

    func testContentBlockingPolicyReplacementUpdatesVisibleSummaryAndDoesNotDuplicateEquivalentRules() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                Self.validRuleListDefinition(name: "SumiParityInitialRulesA"),
                Self.validRuleListDefinition(name: "SumiParityInitialRulesB"),
            ])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()
        let initialSummary = normalTabController.contentBlockingAssetSummary
        XCTAssertEqual(initialSummary.globalRuleListCount, 2)
        XCTAssertEqual(initialSummary.updateRuleCount, 2)
        XCTAssertTrue(initialSummary.isContentBlockingFeatureEnabled)

        let replacementPolicy = SumiContentBlockingPolicy.enabled(ruleLists: [
            Self.validRuleListDefinition(name: "SumiParityReplacementRules")
        ])
        service.setPolicy(replacementPolicy)
        let replacementSummary = await waitForContentBlockingSummary(on: normalTabController) {
            $0.globalRuleListCount == 1 && $0.updateRuleCount == 1
        }

        XCTAssertTrue(replacementSummary.isInstalled)
        XCTAssertTrue(replacementSummary.isContentBlockingFeatureEnabled)

        service.setPolicy(replacementPolicy)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 1)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.updateRuleCount, 1)
    }

    func testContentBlockingSummaryPublisherEmitsCurrentAndReplacementSummaries() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        let disabledSummary = normalTabController.contentBlockingAssetSummary
        let replacementPolicy = SumiContentBlockingPolicy.enabled(ruleLists: [
            Self.validRuleListDefinition(name: "SumiParityPublisherRules")
        ])

        let summaries = await withCheckedContinuation { continuation in
            var observedSummaries = [SumiNormalTabContentBlockingAssetSummary]()
            var cancellable: AnyCancellable?
            cancellable = normalTabController.contentBlockingAssetSummaryPublisher.sink { summary in
                observedSummaries.append(summary)
                if observedSummaries.count == 1 {
                    Task { @MainActor in
                        service.setPolicy(replacementPolicy)
                    }
                } else if observedSummaries.count == 2 {
                    continuation.resume(returning: observedSummaries)
                    cancellable?.cancel()
                }
            }
        }

        XCTAssertEqual(summaries[0], disabledSummary)
        XCTAssertEqual(summaries[1].globalRuleListCount, 1)
        XCTAssertEqual(summaries[1].updateRuleCount, 1)
        XCTAssertTrue(summaries[1].isContentBlockingFeatureEnabled)
    }

    func testCleanupAfterInstalledContentBlockingAssetsIsIdempotentAndPreservesCurrentVisibleSummary() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                Self.validRuleListDefinition(name: "SumiParityCleanupRules")
            ])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        let installedSummary = normalTabController.contentBlockingAssetSummary

        normalTabController.cleanUpBeforeClosing()
        normalTabController.cleanUpBeforeClosing()

        XCTAssertTrue(controller.userScripts.isEmpty)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary, installedSummary)

        service.setPolicy(.disabled)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.userScripts.isEmpty)
        XCTAssertTrue(normalTabController.contentBlockingAssetSummary.isInstalled)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 1)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.updateRuleCount, 1)
        XCTAssertFalse(normalTabController.contentBlockingAssetSummary.isContentBlockingFeatureEnabled)
    }

    func testCleanupIsIdempotentAndPreventsLaterScriptReplacement() async throws {
        let provider = SumiNormalTabUserScripts(
            managedUserScripts: [
                ParityUserScript(context: "sumiParityCleanupInitial", sourceMarker: "__sumiParityCleanupInitial")
            ]
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        normalTabController.cleanUpBeforeClosing()
        normalTabController.cleanUpBeforeClosing()

        XCTAssertTrue(controller.userScripts.isEmpty)

        provider.replaceManagedUserScripts([
            ParityUserScript(context: "sumiParityCleanupReplacement", sourceMarker: "__sumiParityCleanupReplacement")
        ])
        await normalTabController.replaceNormalTabUserScripts(with: provider)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.userScripts.isEmpty)
        XCTAssertEqual(installedScriptCount(containing: "__sumiParityCleanupReplacement", in: controller), 0)
    }

    func testMessageHandlerForwardingFollowsManagedScriptReplacement() async throws {
        let firstDelivered = expectation(description: "first managed handler delivered")
        let secondDelivered = expectation(description: "replacement managed handler delivered")
        let context = "sumiParityForwarding"
        let firstScript = ParityUserScript(context: context, sourceMarker: "__sumiParityForwardingFirst")
        let secondScript = ParityUserScript(context: context, sourceMarker: "__sumiParityForwardingSecond")
        let provider = SumiNormalTabUserScripts(managedUserScripts: [firstScript])
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        firstScript.onMessage = { message in
            XCTAssertEqual(message.name, context)
            XCTAssertTrue(message.webView === webView)
            firstDelivered.fulfill()
        }
        secondScript.onMessage = { message in
            XCTAssertEqual(message.name, context)
            XCTAssertTrue(message.webView === webView)
            secondDelivered.fulfill()
        }
        try await loadBlankDocument(into: webView)

        try await postMessage(to: context, in: webView)
        await fulfillment(of: [firstDelivered], timeout: 5.0)

        provider.replaceManagedUserScripts([secondScript])
        await normalTabController.replaceNormalTabUserScripts(with: provider)

        try await postMessage(to: context, in: webView)
        await fulfillment(of: [secondDelivered], timeout: 5.0)
    }

    func testReplyCapableHandlerForwardsOriginalMessage() async throws {
        let context = "sumiParityReplyForwarding"
        let replyScript = ReplyParityUserScript(context: context, sourceMarker: "__sumiParityReplyForwarding")
        let provider = SumiNormalTabUserScripts(managedUserScripts: [replyScript])
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        let delivered = expectation(description: "reply handler delivered original message")
        replyScript.onReply = { message in
            XCTAssertEqual(message.name, context)
            XCTAssertTrue(message.webView === webView)
            XCTAssertEqual(message.frameInfo.securityOrigin.host, "example.com")
            delivered.fulfill()
            return #"{"context":"\#(context)","id":"reply-id","result":{"accepted":true}}"#
        }
        try await loadBlankDocument(into: webView)

        let response = try await evaluateReturningString(
            """
            const response = await window.webkit.messageHandlers["\(context)"].postMessage({
                context: "\(context)",
                featureName: "parity",
                method: "reply",
                id: "reply-id",
                params: { value: "round-trip" }
            });
            return response;
            """,
            in: webView
        )

        XCTAssertTrue(response.contains(#""accepted":true"#), response)
        await fulfillment(of: [delivered], timeout: 5.0)
    }

    func testReleasedReplyHandlerReturnsUnavailableError() async throws {
        let context = "sumiParityReleasedReply"
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController()
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        let webView = makeWebView(userContentController: controller)
        try await loadBlankDocument(into: webView)

        weak var weakScript: ReplyParityUserScript?
        do {
            let replyScript = ReplyParityUserScript(context: context, sourceMarker: "__sumiParityReleasedReply")
            weakScript = replyScript
            let transientProvider = SumiNormalTabUserScripts(managedUserScripts: [replyScript])
            await normalTabController.replaceNormalTabUserScripts(with: transientProvider)
        }
        XCTAssertNil(weakScript)

        let response = try await evaluateReturningString(
            """
            try {
                await window.webkit.messageHandlers["\(context)"].postMessage({
                    context: "\(context)",
                    featureName: "parity",
                    method: "reply",
                    id: "released",
                    params: {}
                });
                return "resolved";
            } catch (error) {
                return String(error && (error.message || error));
            }
            """,
            in: webView
        )

        XCTAssertTrue(response.contains("Script message handler is unavailable."), response)
    }

    private func postMessage(to context: String, in webView: WKWebView) async throws {
        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (!handler) { throw new Error("missing handler \(context)"); }
            handler.postMessage({
                context: "\(context)",
                featureName: "parity",
                method: "notify",
                params: { value: "round-trip" }
            });
            """,
            in: webView
        )
    }

    private func installedScriptCount(
        containing marker: String,
        in controller: WKUserContentController
    ) -> Int {
        controller.userScripts.filter { $0.source.contains(marker) }.count
    }

    private static func validRuleListDefinition(name: String) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "\(name)-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*sumi-parity-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    private func waitForContentBlockingSummary(
        on controller: SumiNormalTabUserContentControlling,
        where predicate: @escaping (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async -> SumiNormalTabContentBlockingAssetSummary {
        let currentSummary = controller.contentBlockingAssetSummary
        if currentSummary.isInstalled, predicate(currentSummary) {
            return currentSummary
        }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = controller.contentBlockingAssetSummaryPublisher.sink { summary in
                guard predicate(summary) else { return }
                continuation.resume(returning: summary)
                cancellable?.cancel()
            }
        }
    }

    private func makeWebView(userContentController: WKUserContentController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
    }

    private func loadBlankDocument(into webView: WKWebView) async throws {
        let didFinish = expectation(description: "blank document loaded")
        let delegate = ParityNavigationDelegateBox {
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
        in webView: WKWebView
    ) async throws {
        let wrappedScript = """
        (() => {
        \(script)
        return null;
        })();
        """

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(wrappedScript) { value, error in
                _ = value
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func evaluateReturningString(
        _ script: String,
        in webView: WKWebView
    ) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return value as? String ?? String(describing: value)
    }
}

@MainActor
private final class ParityUserScript: NSObject, SumiUserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]
    var onMessage: ((WKScriptMessage) -> Void)?

    init(context: String, sourceMarker: String) {
        self.source = "window.\(sourceMarker) = true;"
        self.messageNames = [context]
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        onMessage?(message)
    }
}

@MainActor
private final class ReplyParityUserScript: NSObject, SumiUserScript, WKScriptMessageHandlerWithReply {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]
    var onReply: ((WKScriptMessage) -> String)?

    init(context: String, sourceMarker: String) {
        self.source = "window.\(sourceMarker) = true;"
        self.messageNames = [context]
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        return (onReply?(message) ?? #"{"result":{}}"#, nil)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        _ = message
    }
}

private final class ParityNavigationDelegateBox: NSObject, WKNavigationDelegate {
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
