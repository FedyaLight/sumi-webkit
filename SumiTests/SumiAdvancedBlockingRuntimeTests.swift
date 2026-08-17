import ContentBlockerConverter
import CryptoKit
import FilterEngine
import WebKit
import XCTest

@testable import Sumi

final class SumiAdvancedBlockingRuntimeTests: XCTestCase {
    func testArchivePublishesNativeAndAdvancedArtifactsAsOneGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let artifacts = try fixture.makeAdvancedArtifacts()
        let manifest = makeManifest(
            generationID: "complete",
            advanced: artifacts.descriptor
        )

        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [:],
            stagedAdvancedArtifactURLs: artifacts.sources
        )

        let active = try await fixture.archive.activeManifest()
        XCTAssertEqual(active?.activeGenerationId, "complete")
        try await fixture.archive.validateCompiledShardFiles(for: manifest)
        let generation = try fixture.archive.generationDirectoryURL(
            generationId: "complete"
        )
        for relativePath in artifacts.sources.keys {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: generation.appendingPathComponent(relativePath).path
                )
            )
        }
    }

    func testArchiveRejectsPartialAdvancedGenerationWithoutReplacingActive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stable = makeManifest(generationID: "stable", advanced: nil)
        try await fixture.archive.commit(
            manifest: stable,
            stagedCompiledShardURLs: [:]
        )
        let artifacts = try fixture.makeAdvancedArtifacts()
        let incompleteSources = artifacts.sources.filter {
            $0.key != ".webext/meta.bin"
        }

        do {
            try await fixture.archive.commit(
                manifest: makeManifest(
                    generationID: "incomplete",
                    advanced: artifacts.descriptor
                ),
                stagedCompiledShardURLs: [:],
                stagedAdvancedArtifactURLs: incompleteSources
            )
            XCTFail("Expected a partial advanced generation to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("staging set mismatch"))
        }

        let active = try await fixture.archive.activeManifest()
        XCTAssertEqual(active?.activeGenerationId, "stable")
    }

    func testRuntimeRestoresFilterEngineAndCompilesOnlyMatchingScriptlets() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let generationID = "runtime"
        let generation = fixture.root
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent(generationID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation,
            withIntermediateDirectories: true
        )
        let builder = try WebExtension(
            containerURL: generation,
            version: SafariVersion.autodetect()
        )
        let rules = [
            "example.org###banner",
            "example.org#?##card:has(.promotion)",
            "example.org#%#console.log('blocked')",
            "example.org#%#//scriptlet('log', 'matched')",
            "example.org#%#//scriptlet('unsupported', 'ignored')",
            "other.example#%#//scriptlet('log', 'not-matched')",
        ].joined(separator: "\n")
        _ = try builder.buildFilterEngine(rules: rules)
        let descriptor = try fixture.descriptorForBuiltEngine(
            in: generation,
            ruleCount: 6
        )
        let runtime = SumiAdvancedBlockingRuntime(
            archive: fixture.archive,
            scriptletCompilerSourceProvider: {
                "globalThis.sumiCompileScriptlet = (name, args) => name === 'unsupported' ? undefined : `compiled:${name}:${args.join(',')}`;"
            }
        )

        let configuration = try await runtime.configuration(
            for: SumiAdvancedBlockingDocumentContext(
                pageURL: try XCTUnwrap(
                    URL(
                        string: "https://example.org/page?utm_source=test&keep=1"
                    )
                ),
                topURL: nil
            ),
            in: makeManifest(
                generationID: generationID,
                advanced: descriptor
            )
        )

        XCTAssertEqual(configuration?.css, ["#banner"])
        XCTAssertEqual(
            configuration?.extendedCSS,
            ["#card:has(.promotion)"]
        )
        XCTAssertEqual(
            configuration?.pageWorldScripts,
            ["compiled:log:matched", "console.log('blocked')"]
        )

        let nonmatching = try await runtime.configuration(
            for: SumiAdvancedBlockingDocumentContext(
                pageURL: try XCTUnwrap(
                    URL(string: "https://unmatched.example/page")
                ),
                topURL: nil
            ),
            in: makeManifest(
                generationID: generationID,
                advanced: descriptor
            )
        )
        XCTAssertNil(nonmatching)
    }

    func testRuntimeCachesCompiledConfigurationForRepeatedDocumentLookup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let generationID = "configuration-cache"
        let generation = fixture.root
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent(generationID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation,
            withIntermediateDirectories: true
        )
        let builder = try WebExtension(
            containerURL: generation,
            version: SafariVersion.autodetect()
        )
        _ = try builder.buildFilterEngine(
            rules: "example.org#%#//scriptlet('cached')"
        )
        let descriptor = try fixture.descriptorForBuiltEngine(
            in: generation,
            ruleCount: 1
        )
        let runtime = SumiAdvancedBlockingRuntime(
            archive: fixture.archive,
            scriptletCompilerSourceProvider: {
                "let compileCount = 0; globalThis.sumiCompileScriptlet = () => `compiled:${++compileCount}`;"
            }
        )
        let document = SumiAdvancedBlockingDocumentContext(
            pageURL: try XCTUnwrap(URL(string: "https://example.org/page")),
            topURL: nil
        )
        let manifest = makeManifest(
            generationID: generationID,
            advanced: descriptor
        )

        let first = try await runtime.configuration(
            for: document,
            in: manifest
        )
        let second = try await runtime.configuration(
            for: document,
            in: manifest
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.pageWorldScripts.first, "compiled:1")
    }

    func testPageWorldScriptletsAreBatchedInRuleOrder() {
        let configuration = SumiAdvancedBlockingConfiguration(
            css: [],
            extendedCSS: [],
            pageWorldScripts: ["first()", "  \n", "second()"]
        )

        let bridge = configuration.pageBridgeValue(
            extendedRuntimeSource: "extended-runtime"
        )
        XCTAssertNil(bridge["scriptlets"])
        XCTAssertNil(bridge["js"])
        XCTAssertEqual(
            configuration.pageWorldSource,
            "try { first() } catch {}\ntry { second() } catch {}"
        )
    }

    @MainActor
    func testPageRuntimeUsesDocumentStartAllFramesAndOneWayTransport() throws {
        let source = try SumiAdvancedBlockingResourceLoader.pageRuntimeSource()
        let script = SumiAdvancedBlockingPageScript(runtimeSource: source) {
            _ in nil
        }

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.forMainFrameOnly)
        XCTAssertFalse(script.requiresRunInPageContentWorld)
        XCTAssertLessThan(script.source.utf8.count, source.utf8.count)
        XCTAssertTrue(script.source.contains("handler.postMessage"))
        XCTAssertFalse(script.source.contains("await handler.postMessage"))
        XCTAssertFalse(script is WKScriptMessageHandlerWithReply)
        XCTAssertFalse(script.source.contains("document.createElement(\"script\")"))
        XCTAssertFalse(script.source.contains("createObjectURL"))
        XCTAssertFalse(script.source.contains("stopImmediatePropagation"))
        XCTAssertEqual(
            script.messageNames,
            [SumiAdvancedBlockingPageScript.messageName]
        )
    }

    @MainActor
    func testBlankFrameUsesTopDocumentForAdvancedRuleLookup() throws {
        let topURL = try XCTUnwrap(URL(string: "https://example.org/page"))
        let blankURL = try XCTUnwrap(URL(string: "about:blank"))

        XCTAssertEqual(
            SumiAdvancedBlockingPageScript.documentContext(
                pageURL: blankURL,
                topURL: topURL,
                isMainFrame: false
            ),
            SumiAdvancedBlockingDocumentContext(
                pageURL: topURL,
                topURL: topURL
            )
        )
        XCTAssertNil(
            SumiAdvancedBlockingPageScript.documentContext(
                pageURL: blankURL,
                topURL: topURL,
                isMainFrame: true
            )
        )
    }

    @MainActor
    func testBootstrapDocumentURLSurvivesMissingFrameRequestURL() throws {
        let documentURL = try XCTUnwrap(
            URL(string: "https://example.org/reloaded")
        )

        XCTAssertEqual(
            SumiAdvancedBlockingPageScript.documentContext(
                messageBody: ["pageURL": documentURL.absoluteString],
                pageURL: nil,
                topURL: nil,
                isMainFrame: true
            ),
            SumiAdvancedBlockingDocumentContext(
                pageURL: documentURL,
                topURL: nil
            )
        )
    }

    @MainActor
    func testBootstrapTopURLWinsOverStaleWebViewURLForSubframe() throws {
        let frameURL = try XCTUnwrap(URL(string: "https://frame.example/content"))
        let currentTopURL = try XCTUnwrap(URL(string: "https://current.example/page"))
        let staleTopURL = try XCTUnwrap(URL(string: "https://stale.example/page"))

        XCTAssertEqual(
            SumiAdvancedBlockingPageScript.documentContext(
                messageBody: [
                    "pageURL": frameURL.absoluteString,
                    "topURL": currentTopURL.absoluteString,
                ],
                pageURL: nil,
                topURL: staleTopURL,
                isMainFrame: false
            ),
            SumiAdvancedBlockingDocumentContext(
                pageURL: frameURL,
                topURL: currentTopURL
            )
        )
    }

    @MainActor
    func testBootstrapLeavesPageUntouchedWithoutMatchingConfiguration() async throws {
        let runtimeSource = try SumiAdvancedBlockingResourceLoader
            .pageRuntimeSource()
        let pageScript = SumiAdvancedBlockingPageScript(
            runtimeSource: runtimeSource
        ) { _ in nil }
        let userContentController = WKUserContentController()
        userContentController.add(
            pageScript,
            contentWorld: pageScript.getContentWorld(),
            name: SumiAdvancedBlockingPageScript.messageName
        )
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: pageScript)
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.userContentController = userContentController
        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let didFinish = expectation(description: "advanced runtime page loaded")
        let delegate = AdvancedRuntimeNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            "<!doctype html><div id='ad'>advert</div>",
            baseURL: URL(string: "https://example.org")
        )
        await fulfillment(of: [didFinish], timeout: 5)

        var display: String?
        display = try await webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('ad')).display"
        ) as? String
        XCTAssertNotEqual(display, "none")
    }

    @MainActor
    func testOneWayBootstrapAppliesMatchingConfiguration() async throws {
        let runtimeSource = try SumiAdvancedBlockingResourceLoader
            .pageRuntimeSource()
        let pageScript = SumiAdvancedBlockingPageScript(
            runtimeSource: runtimeSource
        ) { _ in
            SumiAdvancedBlockingConfiguration(
                css: ["#ad"],
                extendedCSS: [],
                pageWorldScripts: []
            )
        }
        let userContentController = WKUserContentController()
        userContentController.add(
            pageScript,
            contentWorld: pageScript.getContentWorld(),
            name: SumiAdvancedBlockingPageScript.messageName
        )
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: pageScript)
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let didFinish = expectation(description: "one-way advanced runtime")
        let delegate = AdvancedRuntimeNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            "<!doctype html><div id='ad'>advert</div>",
            baseURL: URL(string: "https://example.org")
        )
        await fulfillment(of: [didFinish], timeout: 5)

        var display: String?
        for _ in 0..<20 where display != "none" {
            display = try await webView.evaluateJavaScript(
                "getComputedStyle(document.getElementById('ad')).display"
            ) as? String
            if display != "none" {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTAssertEqual(display, "none")
    }

    @MainActor
    func testBootstrapDoesNotDelayDOMContentLoadedWhileLookupFinishes() async throws {
        let lookupDelay = Duration.milliseconds(150)
        let pageScript = SumiAdvancedBlockingPageScript(runtimeSource: "") {
            _ in
            try? await Task.sleep(for: lookupDelay)
            return nil
        }
        let userContentController = WKUserContentController()
        userContentController.add(
            pageScript,
            contentWorld: pageScript.getContentWorld(),
            name: SumiAdvancedBlockingPageScript.messageName
        )
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: pageScript)
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.userContentController = userContentController
        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let didFinish = expectation(description: "delayed event page loaded")
        let delegate = AdvancedRuntimeNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            """
            <!doctype html>
            <script>
            const startedAt = performance.now();
            document.addEventListener('DOMContentLoaded', () => {
                document.documentElement.dataset.domContentLoadedDelay =
                    String(performance.now() - startedAt);
            });
            </script>
            """,
            baseURL: URL(string: "https://example.org/delayed-event")
        )
        await fulfillment(of: [didFinish], timeout: 5)

        var delay: Double?
        for _ in 0..<50 where delay?.isFinite != true {
            delay = try await webView.evaluateJavaScript(
                "Number(document.documentElement.dataset.domContentLoadedDelay)"
            ) as? Double
            if delay?.isFinite != true {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTAssertLessThan(
            try XCTUnwrap(delay),
            100
        )
    }

    @MainActor
    func testProductionPageScriptKeepsCosmeticBlockingUnderStrictPageCSP() async throws {
        let runtimeSource = try SumiAdvancedBlockingResourceLoader
            .pageRuntimeSource()
        let pageScript = SumiAdvancedBlockingPageScript(
            runtimeSource: runtimeSource
        ) { _ in
            SumiAdvancedBlockingConfiguration(
                css: ["#csp-ad"],
                extendedCSS: [],
                pageWorldScripts: [
                    "window.__sumiAdvancedScriptletWorld = 'main';",
                    "document.documentElement.dataset.sumiAdvancedJavaScriptWorld = 'isolated';",
                ]
            )
        }
        let userContentController = WKUserContentController()
        userContentController.add(
            pageScript,
            contentWorld: pageScript.getContentWorld(),
            name: SumiAdvancedBlockingPageScript.messageName
        )
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: pageScript)
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.userContentController = userContentController
        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let didFinish = expectation(description: "CSP page loaded")
        let delegate = AdvancedRuntimeNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate

        webView.loadHTMLString(
            """
            <!doctype html>
            <meta http-equiv="Content-Security-Policy" content="script-src 'none'; style-src 'none'">
            <title>advanced CSP fixture</title>
            <div id="csp-ad">advertisement</div>
            """,
            baseURL: URL(string: "https://example.org/csp")
        )
        await fulfillment(of: [didFinish], timeout: 5)

        var markers: [String] = []
        for _ in 0..<50 where markers.count != 2 {
            markers = try await webView.evaluateJavaScript(
                "[document.documentElement.dataset.sumiAdvancedJavaScriptWorld, window.__sumiAdvancedScriptletWorld].filter(Boolean)"
            ) as? [String] ?? []
            if markers.count != 2 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTAssertEqual(markers, ["isolated", "main"])
        var display: String?
        for _ in 0..<50 where display != "none" {
            display = try await webView.evaluateJavaScript(
                "getComputedStyle(document.getElementById('csp-ad')).display"
            ) as? String
            if display != "none" {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        XCTAssertEqual(display, "none")
    }

    private func makeManifest(
        generationID: String,
        advanced: AdvancedBlockingGenerationDescriptor?
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: AdblockCompiledGenerationManifest.currentSchemaVersion,
            activeGenerationId: generationID,
            selectedFilterLists: [],
            networkShards: [],
            advancedBlocking: advanced,
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 0),
            previousGenerationId: nil
        )
    }
}

private final class AdvancedRuntimeNavigationDelegate: NSObject,
    WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
        didFinish()
    }
}

private struct AdvancedArtifacts {
    let descriptor: AdvancedBlockingGenerationDescriptor
    let sources: [String: URL]
}

private struct Fixture {
    let root: URL
    let archive: AdblockGenerationArchive

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiAdvancedBlockingRuntimeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        archive = AdblockGenerationArchive(rootDirectory: root)
    }

    func makeAdvancedArtifacts() throws -> AdvancedArtifacts {
        let values: [(AdvancedBlockingArtifactRole, String, Data)] = [
            (.ruleStorage, ".webext/rules.bin", Data("rules".utf8)),
            (.engineIndex, ".webext/engine.bin", Data("engine".utf8)),
            (.engineMetadata, ".webext/meta.bin", Data("meta".utf8)),
            (.sourceRules, ".webext/rules.txt", Data("source".utf8)),
        ]
        var sources: [String: URL] = [:]
        let artifacts = try values.map { role, relativePath, data in
            let source = root
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: source.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: source)
            sources[relativePath] = source
            return makeArtifact(role: role, path: relativePath, data: data)
        }
        return AdvancedArtifacts(
            descriptor: AdvancedBlockingGenerationDescriptor(
                format: AdvancedBlockingGenerationDescriptor.safariConverterFormat,
                schemaVersion: 1,
                runtimeVersion: "4.3.0",
                ruleCount: values.count,
                artifacts: artifacts
            ),
            sources: sources
        )
    }

    func descriptorForBuiltEngine(
        in generation: URL,
        ruleCount: Int
    ) throws -> AdvancedBlockingGenerationDescriptor {
        let removeParamData = Data(
            """
            [{"action":{"redirect":{"transform":{"queryTransform":{"removeParams":["utm_source"]}}},"type":"redirect"},"condition":{"resourceTypes":["main_frame"],"urlFilter":"^utm_source="},"id":1500000,"priority":1}]
            """.utf8
        )
        let removeParamURL = generation.appendingPathComponent(
            ".webext/removeparam.json"
        )
        try removeParamData.write(to: removeParamURL)
        let values: [(AdvancedBlockingArtifactRole, String)] = [
            (.ruleStorage, ".webext/rules.bin"),
            (.engineIndex, ".webext/engine.bin"),
            (.engineMetadata, ".webext/meta.bin"),
            (.sourceRules, ".webext/rules.txt"),
            (.urlCleaningRules, ".webext/removeparam.json"),
        ]
        let artifacts = try values.map { role, relativePath in
            let data = try Data(
                contentsOf: generation.appendingPathComponent(relativePath)
            )
            return makeArtifact(role: role, path: relativePath, data: data)
        }
        return AdvancedBlockingGenerationDescriptor(
            format: AdvancedBlockingGenerationDescriptor.safariConverterFormat,
            schemaVersion: 1,
            runtimeVersion: "4.3.0",
            ruleCount: ruleCount,
            artifacts: artifacts
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeArtifact(
        role: AdvancedBlockingArtifactRole,
        path: String,
        data: Data
    ) -> AdvancedBlockingGenerationDescriptor.Artifact {
        AdvancedBlockingGenerationDescriptor.Artifact(
            role: role,
            relativePath: path,
            hash: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined(),
            byteSize: data.count
        )
    }
}
