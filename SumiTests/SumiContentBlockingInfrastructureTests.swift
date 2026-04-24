import BrowserServicesKit
import Combine
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiContentBlockingInfrastructureTests: XCTestCase {
    func testDefaultPolicyInstallsNoGlobalRuleListsThroughBSKController() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.contentBlockingAssetsInstalled)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertFalse(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertTrue(controller.sumiUsesNormalTabBrowserServicesKitUserContentController)
        XCTAssertFalse(controller.userScripts.isEmpty)
    }

    func testEnabledPolicyCompilesAndAttachesSmallWebKitRuleList() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()

        let assets = try XCTUnwrap(controller.contentBlockingAssets)
        XCTAssertEqual(assets.globalRuleLists.count, 1)
        XCTAssertEqual(assets.updateEvent.rules.count, 1)
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertNil(service.lastCompilationError)
    }

    func testInvalidRuleDataFailsSafelyWithoutAttachingRules() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                SumiContentRuleListDefinition(
                    name: "SumiInvalidRuleList-\(UUID().uuidString)",
                    encodedContentRuleList: "{]"
                )
            ])
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertFalse(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertNotNil(service.lastCompilationError)
    }

    func testPolicyUpdateReplacesRuleListsOnExistingBSKController() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)

        let enabledAssetsTask = Task {
            await Self.waitForAssets(on: controller) { $0.globalRuleLists.count == 1 }
        }
        service.setPolicy(.enabled(ruleLists: [Self.validRuleListDefinition()]))
        let enabledAssets = await enabledAssetsTask.value
        XCTAssertEqual(enabledAssets.globalRuleLists.count, 1)

        let disabledAssetsTask = Task {
            await Self.waitForAssets(on: controller) { $0.globalRuleLists.isEmpty }
        }
        service.setPolicy(.disabled)
        let disabledAssets = await disabledAssetsTask.value
        XCTAssertEqual(disabledAssets.globalRuleLists.count, 0)
    }

    func testCompiledRuleListsAreCachedAcrossControllersAndScriptReplacement() async throws {
        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()]),
            compiler: compiler
        )

        let firstController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await firstController.awaitContentBlockingAssetsInstalled()
        XCTAssertEqual(compiler.compileCount, 1)

        let secondController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await secondController.awaitContentBlockingAssetsInstalled()
        XCTAssertEqual(compiler.compileCount, 1)

        let replacementProvider = SumiNormalTabUserScripts(
            managedUserScripts: [TestContentBlockingProviderUserScript(source: "window.__sumiReplacementScript = true;")]
        )
        await firstController.replaceUserScripts(with: replacementProvider)
        XCTAssertEqual(compiler.compileCount, 1)
    }

    func testContentBlockingUserScriptsUseNormalProviderPath() async throws {
        let marker = "window.__sumiContentBlockingProviderScript = true;"
        let provider = SumiNormalTabUserScripts(
            contentBlockingUserScripts: [TestContentBlockingProviderUserScript(source: marker)]
        )
        let service = SumiContentBlockingService(policy: .disabled)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider,
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.userScripts.contains { $0.source.contains(marker) })
        XCTAssertTrue(controller.sumiNormalTabUserScriptsProvider === provider)
    }

    func testWebViewCoordinatorAwaitsContentBlockingAssetsBeforeInitialLoad() throws {
        let source = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")

        let waitRange = try XCTUnwrap(source.range(of: "await controller.awaitContentBlockingAssetsInstalled()"))
        let loadRange = try XCTUnwrap(source.range(of: "performLoad()", range: waitRange.upperBound..<source.endIndex))

        XCTAssertLessThan(waitRange.lowerBound, loadRange.lowerBound)
    }

    func testNormalPageInterceptionIsNotRegisteredInSumiSources() throws {
        let source = try Self.sumiSourceCorpus()

        XCTAssertFalse(source.contains("setURLSchemeHandler("))
        XCTAssertFalse(source.contains("WKURLSchemeHandler"))
        XCTAssertFalse(source.contains("URLProtocol"))
        XCTAssertFalse(source.contains("127.0.0.1"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("localhost"))
    }

    private static func validRuleListDefinition() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "SumiTestRuleList-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func sumiSourceCorpus() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sumiURL = repoRoot.appendingPathComponent("Sumi", isDirectory: true)
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

    private static func waitForAssets(
        on controller: UserContentController,
        where predicate: @escaping (UserContentController.ContentBlockingAssets) -> Bool
    ) async -> UserContentController.ContentBlockingAssets {
        if let assets = controller.contentBlockingAssets, predicate(assets) {
            return assets
        }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = controller.$contentBlockingAssets.sink { assets in
                guard let assets, predicate(assets) else { return }
                continuation.resume(returning: assets)
                cancellable?.cancel()
            }
        }
    }
}

@MainActor
private final class CountingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private(set) var compileCount = 0

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        await wrapped.lookUpContentRuleList(forIdentifier: identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compileCount += 1
        return try await wrapped.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedContentRuleList
        )
    }
}

private final class TestContentBlockingProviderUserScript: NSObject, UserScript {
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
