import BrowserServicesKit
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

        let seedMarker = "/* SUMI_EC_PAGE_BRIDGE:test */"
        let seedScript = WKUserScript(
            source: seedMarker,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com"),
            additionalUserScripts: [seedScript]
        )

        let controller = try XCTUnwrap(configuration.userContentController as? UserContentController)
        await controller.awaitContentBlockingAssetsInstalled()

        let sources = configuration.userContentController.userScripts.map(\.source)
        XCTAssertFalse(sources.contains(templateMarker))
        XCTAssertEqual(sources.filter { $0 == seedMarker }.count, 1)
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
    }
}
