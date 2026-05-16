import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockNativeCSSWebKitSmokeTests: XCTestCase {
    func testTrackedNativeCosmeticFixtureExistsOutsideIgnoredManualTests() throws {
        let fixtureURL = try Self.fixtureURL()
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
        XCTAssertTrue(fixtureURL.path.contains("/SumiTests/Fixtures/Adblock/"))
        XCTAssertFalse(fixtureURL.path.contains("/ManualTests/"))
        XCTAssertTrue(fixture.contains("keep-visible"))
        XCTAssertTrue(fixture.contains("ad-banner"))
        XCTAssertTrue(fixture.contains("sponsored"))
        XCTAssertTrue(fixture.contains("#sponsor.card[data-ad=\"1\"]"))
    }

    func testNativeCSSContentRuleListHidesFixtureElementsInWebKit() async throws {
        let output = try await AdblockRustCompiler().compile(
            AdblockCompilationInput(
                sourceIdentifier: "SumiNativeCSSWebKitSmoke-\(UUID().uuidString)",
                filterTexts: AdblockWebKitRuleListStore.tinyFixtureFilters,
                selectedOutputGroups: [.nativeCosmeticCSS]
            )
        )
        let group = try XCTUnwrap(output.groups.first { $0.kind == .nativeCosmeticCSS })
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [group.definition])
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 1)

        assertNoAdblockProductionJS(in: controller)

        let webView = makeWebView(userContentController: controller)
        let html = try String(contentsOf: Self.fixtureURL(), encoding: .utf8)

        try await loadHTML(
            html,
            baseURL: URL(string: "https://example.test/native-css-cosmetic.html")!,
            into: webView
        )

        let visibility = try await elementVisibility(in: webView)
        XCTAssertEqual(visibility["control"], true)
        XCTAssertEqual(visibility["adBanner"], false)
        XCTAssertEqual(visibility["sponsored"], false)
        XCTAssertEqual(visibility["attributeTarget"], false)
    }

    func testNativeCSSFixtureElementsRemainVisibleWithoutCosmeticRuleList() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 0)

        assertNoAdblockProductionJS(in: controller)

        let webView = makeWebView(userContentController: controller)
        let html = try String(contentsOf: Self.fixtureURL(), encoding: .utf8)

        try await loadHTML(
            html,
            baseURL: URL(string: "https://example.test/native-css-cosmetic.html")!,
            into: webView
        )

        let visibility = try await elementVisibility(in: webView)
        XCTAssertEqual(visibility["control"], true)
        XCTAssertEqual(visibility["adBanner"], true)
        XCTAssertEqual(visibility["sponsored"], true)
        XCTAssertEqual(visibility["attributeTarget"], true)
    }

    func testEnhancedRuntimeFixtureHidesOnlyInEnhancedScriptPath() async throws {
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [
                AdblockEnhancedResource(
                    name: "sumi-hide",
                    kind: .scriptlet,
                    sourceRule: "example.test##+js(sumi-hide, .enhanced-ad)"
                ),
            ],
            scriptletInvocations: [
                AdblockScriptletInvocation(
                    resourceName: "sumi-hide",
                    parameters: [".enhanced-ad"],
                    includeDomains: ["example.test"],
                    excludeDomains: [],
                    sourceRule: "example.test##+js(sumi-hide, .enhanced-ad)",
                    diagnosticSource: "test"
                ),
            ],
            unsupportedDiagnostics: []
        )
        let script = try XCTUnwrap(
            SumiAdblockEnhancedRuntime.makeScript(
                bundle: runtimeBundle,
                pageURL: URL(string: "https://example.test/enhanced.html")
            )
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: SumiNormalTabUserScripts(managedUserScripts: [script])
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.replaceNormalTabUserScripts(
            with: SumiNormalTabUserScripts(managedUserScripts: [script])
        )

        let webView = makeWebView(userContentController: controller)
        try await loadHTML(
            """
            <!doctype html>
            <html><body>
              <div class="keep-visible">control</div>
              <div class="enhanced-ad">enhanced target</div>
            </body></html>
            """,
            baseURL: URL(string: "https://example.test/enhanced.html")!,
            into: webView
        )

        let result = try await webView.evaluateJavaScript(
            """
            (() => ({
              control: getComputedStyle(document.querySelector('.keep-visible')).display !== 'none',
              enhanced: document.querySelector('.enhanced-ad').hasAttribute('hidden'),
              marker: document.querySelector('.enhanced-ad').getAttribute('data-sumi-adblock-enhanced-applied')
            }))();
            """
        )
        let visibility = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(visibility["control"] as? Bool, true)
        XCTAssertEqual(visibility["enhanced"] as? Bool, true)
        XCTAssertEqual(visibility["marker"] as? String, "true")
    }

    func testAdblockSourceStillHasNoEnhancedRuntimeScriptletBridgeWebExtensionOrScheduler() throws {
        let corpus = try Self.sumiSourceCorpus()
        let adblockSources = try Self.sourceCorpus(
            including: [
                "Sumi/ContentBlocking/SumiAdBlockingModule.swift",
                "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift",
                "Sumi/ContentBlocking/SumiAdblockUpdatePipeline.swift",
            ]
        )

        for forbidden in [
            "WKWebExtension",
            "MutationObserver",
            "addScriptMessageHandler",
            "sumiAdblockBridge",
            "adblockBridge",
            "WKUserScript",
            "addUserScript",
        ] {
            XCTAssertFalse(adblockSources.localizedCaseInsensitiveContains(forbidden), forbidden)
        }

        for forbidden in [
            "networkContentRule(from:",
            "cosmeticContentRule(from:",
            "escapedLooseURLFilter",
        ] {
            XCTAssertFalse(corpus.contains(forbidden), forbidden)
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

    private func loadHTML(
        _ html: String,
        baseURL: URL,
        into webView: WKWebView
    ) async throws {
        let didFinish = expectation(description: "html loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: baseURL)
        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
    }

    private func elementVisibility(in webView: WKWebView) async throws -> [String: Bool] {
        let script = """
        (() => {
          const isVisible = (selector) => {
            const element = document.querySelector(selector);
            if (!element) { return false; }
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
          };
          return {
            control: isVisible('.keep-visible'),
            adBanner: isVisible('.ad-banner'),
            sponsored: isVisible('.sponsored'),
            attributeTarget: isVisible('#sponsor.card[data-ad="1"]')
          };
        })();
        """
        let result = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(result as? [String: Bool])
    }

    private func assertNoAdblockProductionJS(
        in userContentController: WKUserContentController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sources = userContentController.userScripts.map(\.source).joined(separator: "\n")
        let providerSources = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .map(\.source)
            .joined(separator: "\n") ?? ""
        let handlerNames = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .flatMap(\.messageNames)
            .joined(separator: "\n") ?? ""

        for marker in ["adblock", "ad-block", "SumiAdBlocking", "sumiAdBlocking"] {
            XCTAssertFalse(sources.localizedCaseInsensitiveContains(marker), marker, file: file, line: line)
            XCTAssertFalse(providerSources.localizedCaseInsensitiveContains(marker), marker, file: file, line: line)
            XCTAssertFalse(handlerNames.localizedCaseInsensitiveContains(marker), marker, file: file, line: line)
        }
    }

    private static func fixtureURL() throws -> URL {
        let url = repoRoot()
            .appendingPathComponent("SumiTests", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("Adblock", isDirectory: true)
            .appendingPathComponent("native-css-cosmetic.html")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private static func sourceCorpus(including relativePaths: [String]) throws -> String {
        try relativePaths
            .map { try source(named: $0) }
            .joined(separator: "\n")
    }

    private static func sumiSourceCorpus() throws -> String {
        let sumiURL = repoRoot().appendingPathComponent("Sumi", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sumiURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var corpus = ""
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            corpus += try String(contentsOf: url, encoding: .utf8)
            corpus += "\n"
        }
        return corpus
    }

    private static func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onFinish()
    }
}
