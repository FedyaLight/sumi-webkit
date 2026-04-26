import BrowserServicesKit
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserConfigurationNormalTabTests: XCTestCase {
    func testNormalTabConfigurationUsesBSKControllerAndProfileStore() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertTrue(
            configuration.userContentController
                .sumiUsesNormalTabBrowserServicesKitUserContentController
        )
        XCTAssertNotNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        XCTAssertTrue(configuration.userContentController is UserContentController)
        XCTAssertTrue(configuration.processPool === browserConfiguration.normalTabProcessPool)
        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()
        XCTAssertFalse(configuration.userContentController.userScripts.isEmpty)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
    }

    func testNormalTabConfigurationCreatesDistinctControllersWithSharedProcessPool() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let first = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://first.example")
        )
        let second = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://second.example")
        )

        XCTAssertFalse(first.userContentController === second.userContentController)
        XCTAssertTrue(first.processPool === second.processPool)
        XCTAssertTrue(first.processPool === browserConfiguration.normalTabProcessPool)
    }

    func testNormalTabConfigurationDoesNotCopyTemplateScripts() async throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let templateMarker = "window.__sumiTemplateScriptShouldNotCopy = true;"
        browserConfiguration.webViewConfiguration.userContentController.addUserScript(
            WKUserScript(
                source: templateMarker,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let seedMarker = "window.__sumiManagedProviderScript = true;"
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: [TestNormalTabUserScript(source: seedMarker)]
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com"),
            userScriptsProvider: scriptsProvider
        )

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        let sources = configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(sources.contains { $0.contains(templateMarker) })
        XCTAssertEqual(sources.filter { $0.contains(seedMarker) }.count, 1)
    }

    func testEphemeralProfileUsesNonPersistentDataStore() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile.createEphemeral()
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://private.example")
        )

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)
    }

    func testAuxiliaryConfigurationsDoNotInstallTabSuspensionBridge() {
        let browserConfiguration = BrowserConfiguration()
        let peekConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(surface: .peek)
        let miniWindowConfiguration = browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow)

        assertNoTabSuspensionBridge(in: peekConfiguration)
        assertNoTabSuspensionBridge(in: miniWindowConfiguration)
    }

    func testCacheOptimizedConfigurationIsAuxiliaryOnly() {
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.cacheOptimizedWebViewConfiguration()

        assertNoTabSuspensionBridge(in: configuration)
    }

    func testNormalTabConfigurationInstallsCoreScriptProvider() throws {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")
        let tab = Tab(url: URL(string: "https://example.com/core")!)
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: tab.url,
            userScriptsProvider: tab.normalTabUserScriptsProvider(for: tab.url)
        )

        let provider = try XCTUnwrap(configuration.userContentController.sumiNormalTabUserScriptsProvider)
        let sources = provider.userScripts.map(\.source).joined(separator: "\n")

        XCTAssertTrue(sources.contains("sumiLinkInteraction_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiIdentity_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("sumiTabSuspension_\(tab.id.uuidString)"))
        XCTAssertTrue(sources.contains("__sumiTabSuspension"))
    }

    func testTabSuspensionBridgeScriptIsMainFrameOnly() throws {
        let tab = Tab(name: "Bridge")
        let bridgeScript = try XCTUnwrap(
            tab.normalTabCoreUserScripts().first { script in
                script.source.contains("__sumiTabSuspension")
            }
        )

        XCTAssertTrue(bridgeScript.source.contains("sumiTabSuspension_"))
        XCTAssertTrue(bridgeScript.source.contains("tabSuspension"))
        XCTAssertTrue(bridgeScript.forMainFrameOnly)
    }

    func testPrimaryTabSetupUsesCentralFactoryNotFaviconOnlyFactoryOrScriptRemoval() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(source.contains("SumiDDGFaviconUserContentControllerFactory"))
        XCTAssertFalse(source.contains("removeAllUserScripts"))

        let lifecycleSourceURL = repoRoot
            .appendingPathComponent("Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift")
        let lifecycleSource = try String(contentsOf: lifecycleSourceURL, encoding: .utf8)
        XCTAssertFalse(lifecycleSource.contains("injectDocumentIdleScripts"))
        XCTAssertFalse(lifecycleSource.contains("evaluateJavaScript"))
    }

    func testCoordinatorDoesNotCreateNormalWebViewsOrFallbackToPeek() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("createWebViewInternal"))
        XCTAssertFalse(source.contains("normalTabWebViewConfiguration"))
        XCTAssertFalse(source.contains("auxiliaryWebViewConfiguration"))
        XCTAssertFalse(source.contains("surface: .peek"))
        XCTAssertFalse(source.contains("FocusableWKWebView(frame: .zero"))
        XCTAssertTrue(source.contains("tab.ensureWebView()"))
        XCTAssertTrue(source.contains("tab.makeNormalTabWebView"))
    }

    private func assertNoTabSuspensionBridge(
        in configuration: WKWebViewConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let source = configuration.userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")

        XCTAssertFalse(source.contains("__sumiTabSuspension"), file: file, line: line)
        XCTAssertFalse(source.contains("sumiTabSuspension_"), file: file, line: line)
        XCTAssertFalse(source.contains("tabSuspension"), file: file, line: line)
    }
}

private final class TestNormalTabUserScript: NSObject, UserScript {
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
