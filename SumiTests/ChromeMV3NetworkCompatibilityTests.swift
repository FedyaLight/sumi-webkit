import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3NetworkCompatibilityTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDNRManifestRulesetModelParsesStaticRulesetDeterministically()
        throws
    {
        let root = try temporaryDirectory(named: "dnr-static")
        try writeRules(
            [
                blockRule(id: 1, urlFilter: "ads.example.com"),
                allowRule(id: 2, priority: 2, urlFilter: "trusted.example.com"),
            ],
            to: root.appendingPathComponent("rules.json")
        )
        let manifest = try manifest(rulePath: "rules.json")

        let first = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: manifest,
            generatedBundleRootURL: root
        )
        let second = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: manifest,
            generatedBundleRootURL: root
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.declaresDeclarativeNetRequest)
        XCTAssertEqual(first.rulesets.first?.id, "rules_1")
        XCTAssertEqual(first.totalParsedRuleCount, 2)
        XCTAssertEqual(first.enabledRulesetIDs, ["rules_1"])
        XCTAssertFalse(first.dnrAvailableInProduct)
        XCTAssertFalse(first.dnrProductEnforcementAvailable)
        XCTAssertFalse(first.runtimeLoadable)
    }

    func testUnsafeMissingInvalidJSONAndDuplicateRulesAreDiagnosed() throws {
        let root = try temporaryDirectory(named: "dnr-diagnostics")
        try "{".write(
            to: root.appendingPathComponent("invalid.json"),
            atomically: true,
            encoding: .utf8
        )
        try writeRules(
            [
                blockRule(id: 7, urlFilter: "one"),
                blockRule(id: 7, urlFilter: "two"),
            ],
            to: root.appendingPathComponent("duplicates.json")
        )
        let unsafeManifest = manifestModel(rulePath: "../rules.json")
        let missingManifest = manifestModel(rulePath: "missing.json")
        let invalidManifest = manifestModel(rulePath: "invalid.json")
        let duplicateManifest = manifestModel(rulePath: "duplicates.json")

        let unsafe = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: unsafeManifest,
            generatedBundleRootURL: root
        )
        let missing = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: missingManifest,
            generatedBundleRootURL: root
        )
        let invalid = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: invalidManifest,
            generatedBundleRootURL: root
        )
        let duplicate = ChromeMV3DNRStaticRulesetLoader.loadRulesets(
            manifest: duplicateManifest,
            generatedBundleRootURL: root
        )

        XCTAssertTrue(unsafe.diagnostics.contains { $0.code == "unsafeRulesetPath" })
        XCTAssertTrue(missing.diagnostics.contains { $0.code == "missingRulesetFile" })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "invalidRulesetJSON" })
        XCTAssertEqual(duplicate.rulesets.first?.duplicateRuleIDs, [7])
        XCTAssertTrue(duplicate.diagnostics.contains { $0.code == "duplicateRuleID" })
    }

    func testSyntheticEvaluatorMatchesStaticBlockAndPriorityAllow() throws {
        let root = try temporaryDirectory(named: "dnr-evaluator")
        try writeRules(
            [
                blockRule(id: 1, priority: 1, urlFilter: "example.com"),
                allowRule(id: 2, priority: 5, urlFilter: "example.com"),
            ],
            to: root.appendingPathComponent("rules.json")
        )
        let state = ChromeMV3DNRStaticRulesetState(
            model: ChromeMV3DNRStaticRulesetLoader.loadRulesets(
                manifest: try manifest(rulePath: "rules.json"),
                generatedBundleRootURL: root
            )
        )

        let result = ChromeMV3DNRSyntheticEvaluator.evaluate(
            staticRulesetState: state,
            request: .fixture(url: "https://example.com/app.js")
        )

        XCTAssertEqual(result.matchedRules.map(\.ruleID), [2, 1])
        XCTAssertEqual(result.selectedActionType, .allow)
        XCTAssertEqual(result.outcome, "allowed")
        XCTAssertFalse(result.dnrProductEnforcementAvailable)
        XCTAssertFalse(result.runtimeLoadable)
    }

    func testUnsupportedDNRRuleActionsAreClassifiedPrecisely() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                [
                    "id": 1,
                    "action": [
                        "type": "redirect",
                        "redirect": ["url": "https://example.com/"],
                    ],
                    "condition": ["urlFilter": "redirect-me"],
                ],
                [
                    "id": 2,
                    "action": [
                        "type": "modifyHeaders",
                        "requestHeaders": [
                            ["header": "Cookie", "operation": "remove"],
                        ],
                    ],
                    "condition": ["urlFilter": "headers"],
                ],
            ],
            options: [.sortedKeys]
        )

        let parsed = ChromeMV3DNRRuleParser.parseRules(
            data: data,
            rulesetID: "rules",
            sourceKind: .staticRuleset
        )

        XCTAssertEqual(parsed.rules.first { $0.id == 1 }?.action.type, .redirect)
        XCTAssertEqual(parsed.rules.first { $0.id == 1 }?.supportStatus, .deferred)
        XCTAssertEqual(parsed.rules.first { $0.id == 2 }?.action.type, .removeHeaders)
        XCTAssertEqual(parsed.rules.first { $0.id == 2 }?.supportStatus, .unsupported)
        XCTAssertTrue(parsed.diagnostics.isEmpty)
    }

    func testDynamicAndSessionRuleStoresAddRemoveReadAndRejectDuplicates()
        throws
    {
        let owner = ChromeMV3DNRRuleStateOwner()
        let dynamicRule = try parsedRule(id: 11, sourceKind: .dynamic)
        let sessionRule = try parsedRule(id: 21, sourceKind: .session)

        let dynamicAdd = owner.updateDynamicRules(
            addRules: [dynamicRule],
            removeRuleIDs: []
        )
        let sessionAdd = owner.updateSessionRules(
            addRules: [sessionRule],
            removeRuleIDs: []
        )
        let duplicateDynamic = owner.updateDynamicRules(
            addRules: [dynamicRule],
            removeRuleIDs: []
        )
        let duplicateSession = owner.updateSessionRules(
            addRules: [sessionRule],
            removeRuleIDs: []
        )
        let dynamicRemove = owner.updateDynamicRules(
            addRules: [],
            removeRuleIDs: [11]
        )
        let sessionRemove = owner.updateSessionRules(
            addRules: [],
            removeRuleIDs: [21]
        )

        XCTAssertTrue(dynamicAdd.succeeded)
        XCTAssertTrue(sessionAdd.succeeded)
        XCTAssertFalse(duplicateDynamic.succeeded)
        XCTAssertFalse(duplicateSession.succeeded)
        XCTAssertEqual(duplicateDynamic.diagnostics.first?.code, "duplicateRuleID")
        XCTAssertTrue(dynamicRemove.succeeded)
        XCTAssertTrue(sessionRemove.succeeded)
        XCTAssertEqual(owner.dynamicRules, [])
        XCTAssertEqual(owner.sessionRules, [])
    }

    func testDNRJSBridgeMethodsWorkInSyntheticHarness() throws {
        let root = try temporaryDirectory(named: "dnr-js")
        try writeRules(
            [blockRule(id: 1, urlFilter: "blocked.js")],
            to: root.appendingPathComponent("rules.json")
        )
        let staticState = ChromeMV3DNRStaticRulesetState(
            model: ChromeMV3DNRStaticRulesetLoader.loadRulesets(
                manifest: try manifest(rulePath: "rules.json"),
                generatedBundleRootURL: root
            )
        )
        let handler = ChromeMV3DNRJSBridgeHandler(
            staticRulesetState: staticState
        )

        let enabled = handler.handle(
            request(
                methodName: "getEnabledRulesets"
            )
        )
        let updateDynamic = handler.handle(
            request(
                methodName: "updateDynamicRules",
                arguments: [
                    .object([
                        "addRules": .array([
                            ruleValue(id: 99, urlFilter: "dynamic.js"),
                        ]),
                    ]),
                ]
            )
        )
        let dynamicRules = handler.handle(
            request(methodName: "getDynamicRules")
        )
        let updateSession = handler.handle(
            request(
                methodName: "updateSessionRules",
                arguments: [
                    .object([
                        "addRules": .array([
                            ruleValue(id: 100, urlFilter: "session.js"),
                        ]),
                    ]),
                ]
            )
        )
        let sessionRules = handler.handle(
            request(methodName: "getSessionRules")
        )
        let outcome = handler.handle(
            request(
                methodName: "testMatchOutcome",
                arguments: [
                    .object([
                        "url": .string("https://example.com/blocked.js"),
                        "type": .string("script"),
                    ]),
                ]
            )
        )

        XCTAssertTrue(enabled.succeeded)
        XCTAssertEqual(enabled.resultPayload, .array([.string("rules_1")]))
        XCTAssertTrue(updateDynamic.succeeded)
        XCTAssertEqual(array(dynamicRules.resultPayload)?.count, 1)
        XCTAssertTrue(updateSession.succeeded)
        XCTAssertEqual(array(sessionRules.resultPayload)?.count, 1)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(object(outcome.resultPayload)?["outcome"], .string("blocked"))
        XCTAssertFalse(outcome.dnrAvailableInProduct)
        XCTAssertFalse(outcome.dnrProductEnforcementAvailable)
        XCTAssertFalse(outcome.runtimeLoadable)
    }

    func testWebRequestCompatibilityAndSyntheticDispatchAreInternalOnly()
        throws
    {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "webRequest Extension",
            "version": "1.0",
            "permissions": [
                "webRequest",
                "webRequestBlocking",
            ],
            "host_permissions": ["https://example.com/*"],
        ])
        let classification =
            ChromeMV3WebRequestCompatibilityClassifier.classify(
                manifest: manifest
            )
        let session = try sharedSession()
        let registry = ChromeMV3WebRequestSyntheticEventRegistry(
            extensionID: session.key.extensionID,
            profileID: session.key.profileID,
            sharedLifecycleSession: session
        )
        _ = registry.addListener(
            eventName: .onBeforeRequest,
            listenerID: "listener"
        )
        let dispatch = registry.emit(
            .beforeRequest(url: "https://example.com/app.js")
        )

        XCTAssertTrue(classification.webRequestAvailableInInternalFixture)
        XCTAssertFalse(classification.webRequestBlockingAvailableInProduct)
        XCTAssertTrue(
            classification.eventClassifications.contains {
                $0.eventName == .onBeforeRequest
                    && $0.statuses.contains(.productBlocked)
                    && $0.statuses.contains(.requiresDNRInstead)
            }
        )
        XCTAssertTrue(dispatch.dispatched, dispatch.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(dispatch.sharedLifecycleSessionID, session.key.lifecycleSessionID)
        XCTAssertEqual(
            dispatch.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .webRequestHarness
        )
        XCTAssertFalse(dispatch.productRequestModified)
    }

    @MainActor
    func testNetworkCompatibilityReportAndModuleIntegrationStayDisabledSafe()
        throws
    {
        let root = try temporaryDirectory(named: "network-report")
        try writeManifestFile(
            [
                "manifest_version": 3,
                "name": "Network Report",
                "version": "1.0",
                "permissions": [
                    "declarativeNetRequest",
                    "webRequest",
                    "webRequestBlocking",
                ],
                "host_permissions": ["https://example.com/*"],
                "declarative_net_request": [
                    "rule_resources": [
                        [
                            "id": "rules_1",
                            "enabled": true,
                            "path": "rules.json",
                        ],
                    ],
                ],
            ],
            to: root.appendingPathComponent("manifest.json")
        )
        try writeRules(
            [blockRule(id: 1, urlFilter: "ads")],
            to: root.appendingPathComponent("rules.json")
        )
        let manifest = try ChromeMV3ManifestValidator.validateManifestFile(
            at: root.appendingPathComponent("manifest.json")
        )
        let report = ChromeMV3NetworkCompatibilityReportGenerator.makeReport(
            manifest: manifest,
            generatedBundleRootURL: root
        )
        let disabled = try makeModule(enabled: false)
        let enabled = try makeModule(enabled: true)

        XCTAssertNil(
            disabled.chromeMV3NetworkCompatibilityReportIfEnabled(
                fromRewrittenBundleRoot: root,
                manifest: manifest,
                writeReport: true
            )
        )
        let moduleReport =
            enabled.chromeMV3NetworkCompatibilityReportIfEnabled(
                fromRewrittenBundleRoot: root,
                manifest: manifest,
                writeReport: true
            )

        XCTAssertEqual(report.dnrManifestRulesetModel.totalParsedRuleCount, 1)
        XCTAssertTrue(report.dnrAvailableInInternalEvaluator)
        XCTAssertFalse(report.dnrAvailableInProduct)
        XCTAssertFalse(report.dnrProductEnforcementAvailable)
        XCTAssertFalse(report.webRequestBlockingAvailableInProduct)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertNotNil(moduleReport)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3NetworkCompatibilityReportWriter.reportFileName
                    ).path
            )
        )
        let inventoryRuntimeLoadable =
            try XCTUnwrap(
                enabled.chromeMV3InventoryDiagnosticsIfEnabled(rootURL: root)?
                    .networkCompatibilityReportSummary?
                    .runtimeLoadable
            )
        XCTAssertFalse(inventoryRuntimeLoadable)
    }

    func testInstallReportIncludesPreciseNetworkCompatibilitySummary()
        throws
    {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "Install Network",
            "version": "1.0",
            "permissions": [
                "declarativeNetRequest",
                "webRequest",
                "webRequestBlocking",
            ],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "rules_1",
                        "enabled": true,
                        "path": "rules.json",
                    ],
                ],
            ],
        ])

        let report = ChromeMV3InstallReporter.report(for: manifest)

        XCTAssertTrue(
            report.networkCompatibilitySummary
                .declaresDeclarativeNetRequest
        )
        XCTAssertEqual(
            report.networkCompatibilitySummary.staticRulesetResourceCount,
            1
        )
        XCTAssertTrue(report.networkCompatibilitySummary.declaresWebRequest)
        XCTAssertTrue(
            report.networkCompatibilitySummary.declaresWebRequestBlocking
        )
        XCTAssertFalse(report.networkCompatibilitySummary.dnrAvailableInProduct)
        XCTAssertFalse(
            report.networkCompatibilitySummary
                .dnrProductEnforcementAvailable
        )
        XCTAssertFalse(
            report.networkCompatibilitySummary
                .webRequestBlockingAvailableInProduct
        )
        XCTAssertTrue(report.warnings.contains { $0.code == "dnrSyntheticEvaluatorOnly" })
        XCTAssertTrue(report.warnings.contains { $0.code == "webRequestBlockingProductBlocked" })
    }

    func testNetworkCompatibilitySourceGuardsKeepProductPathsForbidden()
        throws
    {
        let source = try String(
            contentsOf:
                URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3NetworkCompatibility.swift"
                ),
            encoding: .utf8
        )

        let enabledWord = "tr" + "ue"
        let forbiddenTokens = [
            "Ti" + "mer",
            "DispatchSource" + "Ti" + "mer",
            "Process" + "(",
            "URL" + "Protocol",
            "Browser" + "Config",
            "webExtension" + "Controller",
            "navigation" + "Delegate",
            "dnrAvailableInProduct: " + enabledWord,
            "dnrProductEnforcementAvailable: " + enabledWord,
            "webRequestBlockingAvailableInProduct: " + enabledWord,
            "normalTabRuntimeBridgeAvailable: " + enabledWord,
            "runtimeLoadable: " + enabledWord,
            "productRuntimeExposed: " + enabledWord,
        ]
        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    private func manifest(rulePath: String) throws -> ChromeMV3Manifest {
        try validateManifest([
            "manifest_version": 3,
            "name": "DNR",
            "version": "1.0",
            "permissions": ["declarativeNetRequest"],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "rules_1",
                        "enabled": true,
                        "path": rulePath,
                    ],
                ],
            ],
        ])
    }

    private func manifestModel(rulePath: String) -> ChromeMV3Manifest {
        ChromeMV3Manifest(
            manifestVersion: 3,
            name: "DNR",
            version: "1.0",
            description: nil,
            background: nil,
            permissions: ["declarativeNetRequest"],
            optionalPermissions: [],
            hostPermissions: [],
            contentScripts: [],
            action: nil,
            optionsPage: nil,
            optionsUI: nil,
            webAccessibleResources: [],
            externallyConnectable: nil,
            declarativeNetRequest:
                ChromeMV3DeclarativeNetRequest(
                    ruleResources: [
                        ChromeMV3DeclarativeNetRequestRuleResource(
                            id: "rules_1",
                            enabled: true,
                            path: rulePath
                        ),
                    ]
                ),
            sidePanel: nil,
            oauth2: nil,
            commands: [:],
            minimumChromeVersion: nil,
            browserSpecificSettings: [:],
            devtoolsPage: nil,
            topLevelKeys: [
                "declarative_net_request",
                "manifest_version",
                "name",
                "permissions",
                "version",
            ]
        )
    }

    private func parsedRule(
        id: Int,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) throws -> ChromeMV3DNRRule {
        let data = try JSONSerialization.data(
            withJSONObject: [
                blockRule(id: id, urlFilter: "example.com"),
            ],
            options: [.sortedKeys]
        )
        return try XCTUnwrap(
            ChromeMV3DNRRuleParser.parseRules(
                data: data,
                rulesetID: sourceKind.rawValue,
                sourceKind: sourceKind
            ).rules.first
        )
    }

    private func blockRule(
        id: Int,
        priority: Int = 1,
        urlFilter: String
    ) -> [String: Any] {
        [
            "id": id,
            "priority": priority,
            "action": ["type": "block"],
            "condition": [
                "urlFilter": urlFilter,
                "resourceTypes": ["script"],
            ],
        ]
    }

    private func allowRule(
        id: Int,
        priority: Int = 1,
        urlFilter: String
    ) -> [String: Any] {
        [
            "id": id,
            "priority": priority,
            "action": ["type": "allow"],
            "condition": [
                "urlFilter": urlFilter,
                "resourceTypes": ["script"],
            ],
        ]
    }

    private func ruleValue(
        id: Int,
        urlFilter: String
    ) -> ChromeMV3StorageValue {
        .object([
            "id": .number(Double(id)),
            "priority": .number(1),
            "action": .object(["type": .string("block")]),
            "condition": .object([
                "urlFilter": .string(urlFilter),
                "resourceTypes": .array([.string("script")]),
            ]),
        ])
    }

    private func writeRules(_ rules: [[String: Any]], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: rules,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
    }

    private func validateManifest(
        _ manifest: [String: Any]
    ) throws -> ChromeMV3Manifest {
        let root = try temporaryDirectory(named: "manifest")
        let url = root.appendingPathComponent("manifest.json")
        try writeManifestFile(manifest, to: url)
        return try ChromeMV3ManifestValidator.validateManifestFile(at: url)
    }

    private func writeManifestFile(
        _ manifest: [String: Any],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
    }

    private func request(
        methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: "declarativeNetRequest",
            methodName: methodName,
            invocationMode: .promise,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func object(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func array(
        _ value: ChromeMV3StorageValue?
    ) -> [ChromeMV3StorageValue]? {
        guard case .array(let array) = value else { return nil }
        return array
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3NetworkCompatibilityTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func sharedSession()
        throws -> ChromeMV3ServiceWorkerSharedLifecycleSession
    {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        return try XCTUnwrap(
            registry.session(
                profileID: "network-profile",
                extensionID: "network-extension",
                moduleState: .enabled,
                explicitInternalLifecycleAllowed: true
            )
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3NetworkCompatibilityTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration()
        )
    }
}
