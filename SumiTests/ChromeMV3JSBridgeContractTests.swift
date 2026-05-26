import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3JSBridgeContractTests: XCTestCase {
    func testBridgeRequestEnvelopeEncodingIsDeterministic() throws {
        let first = request(
            namespace: .runtime,
            methodName: "sendMessage",
            arguments: [
                .object([
                    "b": .string("second"),
                    "a": .string("first"),
                ]),
            ],
            mode: .promise
        )
        let second = request(
            namespace: .runtime,
            methodName: "sendMessage",
            arguments: [
                .object([
                    "a": .string("first"),
                    "b": .string("second"),
                ]),
            ],
            mode: .promise
        )

        XCTAssertEqual(first.bridgeCallID, second.bridgeCallID)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(first),
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
        XCTAssertEqual(first.namespace, .runtime)
        XCTAssertEqual(first.invocationMode, .promise)
    }

    func testBridgeResponseEnvelopeEncodingIsDeterministic() throws {
        var firstEnvironment = environment()
        var secondEnvironment = environment()
        let envelope = request(
            namespace: .runtime,
            methodName: "sendMessage",
            arguments: [.object(["type": .string("ping")])],
            mode: .promise
        )

        let first = ChromeMV3JSBridgeContractRouter.route(
            envelope,
            environment: &firstEnvironment
        )
        let second = ChromeMV3JSBridgeContractRouter.route(
            envelope,
            environment: &secondEnvironment
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(first),
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
        XCTAssertFalse(first.runtimeExposureNow)
        XCTAssertFalse(first.jsBridgeAvailableNow)
    }

    func testUnsupportedNamespaceMapsToNamespaceUnsupported() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .unsupported,
                methodName: "anything",
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorContract?.code, .namespaceUnsupported)
        XCTAssertEqual(response.promiseBehavior.wouldReject, true)
    }

    func testUnsupportedMethodMapsToMethodUnsupported() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .runtime,
                methodName: "getManifest",
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorContract?.code, .methodUnsupported)
    }

    func testInvalidArgumentsMapToInvalidArguments() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .tabs,
                methodName: "sendMessage",
                arguments: [
                    .string("not-a-tab-id"),
                    .object(["type": .string("ping")]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorContract?.code, .invalidArguments)
        XCTAssertEqual(
            response.routeResult?.normalizedArguments.status,
            .invalidArguments
        )
    }

    func testRuntimeSendMessageRoutesToModelDispatcher() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .runtime,
                methodName: "sendMessage",
                arguments: [
                    .object(["type": .string("unlock-state")]),
                    .object(["includeTlsChannelId": .bool(false)]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertTrue(
            response.routeResult?.runtimeDispatcherResult?
                .modelHandlerInvoked ?? false
        )
        XCTAssertEqual(
            response.routeResult?.runtimeDispatcherResult?.routeKind,
            .runtimeSendMessage
        )
        XCTAssertEqual(
            response.routeResult?.runtimeDispatcherResult?.responsePayload,
            .object([
                "ok": .bool(true),
                "target": .string("serviceWorkerModel"),
            ])
        )
    }

    func testTabsSendMessageRoutesToModelDispatcherAndPreservesTabID() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .serviceWorker,
                namespace: .tabs,
                methodName: "sendMessage",
                arguments: [
                    .number(1),
                    .object(["type": .string("fill")]),
                    .object(["frameId": .number(0)]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            response.routeResult?.normalizedArguments
                .normalizedPayload["tabId"],
            .number(1)
        )
        XCTAssertEqual(
            response.routeResult?.runtimeDispatcherResult?.routeKind,
            .tabsSendMessage
        )
        XCTAssertEqual(
            response.routeResult?.runtimeDispatcherResult?.responsePayload,
            .object([
                "ok": .bool(true),
                "target": .string("contentScriptModel"),
            ])
        )
    }

    func testRuntimeConnectReturnsPortPreflightAndOpensNoPort() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .runtime,
                methodName: "connect",
                arguments: [.object(["name": .string("vault")])],
                mode: .fireAndForget
            ),
            environment: &environment
        )
        let preflight = response.routeResult?.runtimeDispatcherResult?
            .modelPortPreflight

        XCTAssertFalse(response.succeeded)
        XCTAssertNotNil(preflight)
        XCTAssertFalse(preflight?.canOpenRuntimePortNow ?? true)
        XCTAssertFalse(response.routeResult?.openedRuntimePortNow ?? true)
        XCTAssertFalse(
            response.routeResult?.runtimeDispatcherResult?
                .canOpenPortNow ?? true
        )
    }

    func testTabsConnectReturnsPortPreflightAndOpensNoPort() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .serviceWorker,
                namespace: .tabs,
                methodName: "connect",
                arguments: [
                    .number(1),
                    .object([
                        "name": .string("content"),
                        "frameId": .number(0),
                    ]),
                ],
                mode: .fireAndForget
            ),
            environment: &environment
        )
        let preflight = response.routeResult?.runtimeDispatcherResult?
            .modelPortPreflight

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(
            response.routeResult?.runtimeDispatcherResult?.routeKind,
            .tabsConnect
        )
        XCTAssertNotNil(preflight)
        XCTAssertFalse(preflight?.canOpenRuntimePortNow ?? true)
        XCTAssertFalse(response.routeResult?.openedRuntimePortNow ?? true)
    }

    func testStorageLocalGetRoutesToOperationHandler() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.get",
                arguments: [.string("existing")],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            response.routeResult?.storageOperationResult?.operation,
            .get
        )
        XCTAssertTrue(
            response.routeResult?.storageOperationResult?
                .brokerOperationExecutedInModel ?? false
        )
        XCTAssertEqual(response.resultPayload, .object([
            "existing": .string("value"),
        ]))
    }

    func testStorageLocalSetRoutesAndCreatesOnChangedPayloadButDispatchesNothing()
    {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.set",
                arguments: [
                    .object(["vaultUnlocked": .bool(true)]),
                ],
                mode: .promise
            ),
            environment: &environment
        )
        let storage = response.routeResult?.storageOperationResult

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(storage?.operation, .set)
        XCTAssertEqual(storage?.changedKeys, ["vaultUnlocked"])
        XCTAssertEqual(
            storage?.generatedOnChangedPayload?.wouldDispatchNow,
            false
        )
        XCTAssertFalse(
            response.routeResult?.dispatchedStorageOnChangedNow ?? true
        )
    }

    func testStorageSyncRoutesToDeferredSyncPolicy() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "sync.get",
                arguments: [.null],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorContract?.code, .storageAreaUnavailable)
        XCTAssertEqual(
            response.routeResult?.storageOperationResult?
                .futureLastErrorContract?.code,
            .syncUnavailable
        )
        XCTAssertFalse(
            response.routeResult?.storageOperationResult?
                .brokerOperationExecutedInModel ?? true
        )
    }

    func testStorageArgumentNormalizationCoversRemoveClearAndBytes() {
        var environment = environment()
        let remove = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.remove",
                arguments: [.array([.string("existing")])],
                mode: .promise
            ),
            environment: &environment
        )
        let bytes = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.getBytesInUse",
                arguments: [.null],
                mode: .promise
            ),
            environment: &environment
        )
        let clear = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.clear",
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(remove.succeeded)
        XCTAssertEqual(
            remove.routeResult?.storageOperationResult?.operation,
            .remove
        )
        XCTAssertTrue(bytes.succeeded)
        XCTAssertEqual(
            bytes.routeResult?.storageOperationResult?.operation,
            .getBytesInUse
        )
        XCTAssertTrue(clear.succeeded)
        XCTAssertEqual(
            clear.routeResult?.storageOperationResult?.operation,
            .clear
        )
    }

    func testPermissionsContainsRoutesToAPIContract() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .actionPopup,
                namespace: .permissions,
                methodName: "contains",
                arguments: [
                    .object([
                        "permissions": .array([.string("tabs")]),
                        "origins": .array([
                            .string("https://example.com/*"),
                        ]),
                    ]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(response.resultPayload, .bool(true))
        XCTAssertTrue(
            response.routeResult?.permissionsContainsResult?.wouldReturn
                ?? false
        )
    }

    func testPermissionsRequestRoutesToPromptRequiredContractButNoUI() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .actionPopup,
                namespace: .permissions,
                methodName: "request",
                arguments: [
                    .object([
                        "permissions": .array([.string("history")]),
                    ]),
                ],
                mode: .promise
            ),
            environment: &environment
        )
        let result = response.routeResult?.permissionsRequestResult

        XCTAssertTrue(response.succeeded)
        XCTAssertTrue(result?.wouldRequirePrompt ?? false)
        XCTAssertFalse(result?.canPromptUserNow ?? true)
        XCTAssertFalse(result?.canDispatchPermissionEventNow ?? true)
    }

    func testPermissionsGetAllAndRemoveRouteToAPIContract() {
        var environment = environment()
        let getAll = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .permissions,
                methodName: "getAll",
                mode: .promise
            ),
            environment: &environment
        )
        let remove = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .permissions,
                methodName: "remove",
                arguments: [
                    .object([
                        "permissions": .array([.string("bookmarks")]),
                    ]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(getAll.succeeded)
        XCTAssertNotNil(getAll.routeResult?.permissionsGetAllResult)
        XCTAssertTrue(remove.succeeded)
        XCTAssertEqual(remove.resultPayload, .bool(true))
        XCTAssertFalse(
            remove.routeResult?.permissionsRemoveResult?
                .canDispatchPermissionEventNow ?? true
        )
    }

    func testNativeMessagingConnectAndSendRouteToBlockedPreflight() {
        var environment = environment()
        let connect = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .serviceWorker,
                namespace: .nativeMessaging,
                methodName: "connect",
                arguments: [.string("com.example.password_manager")],
                mode: .fireAndForget
            ),
            environment: &environment
        )
        let send = ChromeMV3JSBridgeContractRouter.route(
            request(
                sourceContext: .serviceWorker,
                namespace: .nativeMessaging,
                methodName:
                    ChromeMV3JSBridgeArgumentNormalizer.nativeSendName(),
                arguments: [
                    .string("com.example.password_manager"),
                    .object(["text": .string("hello")]),
                ],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertFalse(connect.succeeded)
        XCTAssertEqual(connect.lastErrorContract?.code, .nativeMessagingBlocked)
        XCTAssertEqual(
            connect.routeResult?.nativeMessagingPreflight?.operationKind,
            .longLivedNativePort
        )
        let processLaunchAllowedNow = connect.routeResult?.nativeMessagingPreflight?
            .processLaunchAllowedNow
        XCTAssertNotNil(processLaunchAllowedNow)
        XCTAssertEqual(processLaunchAllowedNow, false)
        XCTAssertFalse(send.succeeded)
        XCTAssertEqual(
            send.routeResult?.nativeMessagingPreflight?.operationKind,
            .oneShotNativeMessage
        )
        XCTAssertEqual(send.promiseBehavior.wouldReject, true)
    }

    func testCallbackModeResponseIsRepresented() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .storage,
                methodName: "local.get",
                arguments: [.string("existing")],
                mode: .callback
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertTrue(response.callbackBehavior.callbackModeRequested)
        XCTAssertTrue(response.callbackBehavior.wouldInvokeCallback)
        XCTAssertEqual(response.callbackBehavior.callbackPayload, .object([
            "existing": .string("value"),
        ]))
        XCTAssertFalse(response.promiseBehavior.promiseModeRequested)
    }

    func testPromiseModeResponseIsRepresented() {
        var environment = environment()
        let response = ChromeMV3JSBridgeContractRouter.route(
            request(
                namespace: .runtime,
                methodName: "sendMessage",
                arguments: [.object(["type": .string("ping")])],
                mode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertTrue(response.promiseBehavior.promiseModeRequested)
        XCTAssertTrue(response.promiseBehavior.wouldResolve)
        XCTAssertFalse(response.callbackBehavior.callbackModeRequested)
    }

    func testLastErrorMappingIsDeterministic() throws {
        var firstEnvironment = environment()
        var secondEnvironment = environment()
        let envelope = request(
            namespace: .storage,
            methodName: "sync.set",
            arguments: [.object(["key": .string("value")])],
            mode: .callback
        )

        let first = ChromeMV3JSBridgeContractRouter.route(
            envelope,
            environment: &firstEnvironment
        )
        let second = ChromeMV3JSBridgeContractRouter.route(
            envelope,
            environment: &secondEnvironment
        )

        XCTAssertEqual(first.lastErrorContract, second.lastErrorContract)
        XCTAssertEqual(first.lastErrorContract?.code, .storageAreaUnavailable)
        XCTAssertEqual(first.callbackBehavior.wouldSetRuntimeLastError, true)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(first),
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
    }

    func testMethodCapabilityMatrixKeepsJSExposureFalse() {
        let capabilities = ChromeMV3JSBridgeMethodCapabilityMatrix
            .allCapabilities()

        XCTAssertTrue(capabilities.contains {
            $0.namespace == .runtime && $0.methodName == "sendMessage"
        })
        XCTAssertTrue(capabilities.contains {
            $0.namespace == .storage && $0.methodName == "local.get"
        })
        XCTAssertTrue(capabilities.allSatisfy { $0.exposedToJSNow == false })
        XCTAssertTrue(capabilities.contains {
            $0.namespace == .nativeMessaging
                && $0.requiresNativeHost
        })
    }

    func testPasswordManagerFixtureReportsModelBridgeReadyButRuntimeBlocked()
        throws
    {
        let report = ChromeMV3JSBridgeContractReportGenerator.makeReport(
            extensionID: extensionID,
            profileID: profileID
        )
        let password = report.passwordManagerJSBridgeSummary

        XCTAssertTrue(password.runtimeSendMessageEnvelopeRouteModeled)
        XCTAssertTrue(password.storageLocalEnvelopeRouteModeled)
        XCTAssertTrue(password.permissionsEnvelopeRouteModeled)
        XCTAssertTrue(password.nativeMessagingEnvelopeRouteBlocked)
        XCTAssertFalse(password.contentScriptJSShimInjected)
        XCTAssertFalse(password.extensionPageJSShimInjected)
        XCTAssertFalse(password.serviceWorkerWoken)
        XCTAssertTrue(password.passwordManagerJSBridgeModelReady)
        XCTAssertFalse(password.passwordManagerRuntimeBridgeReady)
        XCTAssertFalse(report.jsBridgeAvailableNow)
        XCTAssertFalse(report.exposedToJSNow)
        XCTAssertFalse(report.canInjectScriptsNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(report),
            try ChromeMV3DeterministicJSON.encodedData(report)
        )
    }

    func testRuntimeReadinessReportIncludesJSBridgeContractSummary() {
        let report = ChromeMV3RuntimeBridgeReadinessReportGenerator.makeReport(
            prerequisitesReport: makePrerequisitesReport(),
            prerequisitesReportPath:
                "/tmp/password-manager-fixture/runtime-bridge-prerequisites-report.json"
        )

        XCTAssertEqual(
            report.jsBridgeContractReportSummary?.reportFileName,
            ChromeMV3JSBridgeContractReportWriter.reportFileName
        )
        XCTAssertTrue(
            report.jsBridgeContractReportSummary?
                .modelBridgeRoutingAvailable ?? false
        )
        XCTAssertFalse(
            report.jsBridgeContractReportSummary?.jsBridgeAvailableNow
                ?? true
        )
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testSumiExtensionsModuleWritesBridgeReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(root: root),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3JSBridgeContractReportWriter.reportFileName
        )

        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport = disabledModule
            .chromeMV3JSBridgeContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3JSBridgeContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.jsBridgeContractReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testSourceLevelGuardsForJSBridgeContractLayer() throws {
        let sources = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let joined = sources.map(\.contents).joined(separator: "\n")

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "WKUser" + "Script(",
            "add" + "UserScript",
            "add" + "ScriptMessageHandler",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "js" + "BridgeAvailableNow\\s*[:=].*" + "tr" + "ue",
            "exposed" + "ToJSNow\\s*[:=].*" + "tr" + "ue",
            "canInject" + "ScriptsNow\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerRuntimeBridgeReady\\s*[:=].*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                joined.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private let extensionID = "extension-a"
    private let profileID = "profile-a"

    private func environment(
        moduleState: ChromeMV3ProfileHostModuleState = .enabled
    ) -> ChromeMV3JSBridgeContractEnvironment {
        ChromeMV3JSBridgeContractEnvironment.passwordManagerModelFixture(
            extensionID: extensionID,
            profileID: profileID,
            moduleState: moduleState
        )
    }

    private func request(
        sourceContext: ChromeMV3JSBridgeSourceContext = .testFixture,
        namespace: ChromeMV3JSBridgeNamespace,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = [],
        mode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3JSBridgeRequestEnvelope {
        ChromeMV3JSBridgeRequestEnvelope(
            extensionID: extensionID,
            profileID: profileID,
            sourceContext: sourceContext,
            namespace: namespace,
            methodName: methodName,
            rawArguments: arguments,
            invocationMode: mode
        )
    }

    private func makePrerequisitesReport(
        root: URL? = nil
    ) -> ChromeMV3RuntimeBridgePrerequisitesReport {
        let rootPath = root?.path ?? "/tmp/password-manager-fixture"
        return ChromeMV3RuntimeBridgePrerequisitesReport(
            schemaVersion: 1,
            id: "runtime-prerequisites-test",
            reportFileName:
                ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName,
            candidateID: "password-manager-fixture",
            generatedRewrittenRootPath: rootPath,
            contextReadinessReportID: "context-readiness-test",
            contextReadinessReportPath:
                URL(fileURLWithPath: rootPath)
                .appendingPathComponent(
                    ChromeMV3ContextReadinessReportWriter.reportFileName
                ).path,
            contextReadinessReportHash: String(repeating: "a", count: 64),
            contextReadinessConsumerDiagnostic:
                ChromeMV3ContextReadinessReportConsumptionDiagnostic(
                    schemaVersion: 1,
                    reportFileName:
                        ChromeMV3ContextReadinessReportWriter.reportFileName,
                    reportPath:
                        URL(fileURLWithPath: rootPath)
                        .appendingPathComponent(
                            ChromeMV3ContextReadinessReportWriter
                                .reportFileName
                        ).path,
                    state: .ready,
                    canImplementRecommendedBranch: true,
                    nextRequiredPromptCategory:
                        .addRuntimeBridgePrerequisites,
                    rawNextRequiredPromptCategory:
                        "addRuntimeBridgePrerequisites",
                    allowedNextRequiredPromptCategories: [
                        "addRuntimeBridgePrerequisites",
                    ],
                    blockingReasons: [],
                    warnings: [],
                    requiredActions: []
                ),
            manifestFacts: manifestFacts(rootPath: rootPath),
            runtimeMessagingPrerequisites: runtimeMessagingPrerequisites(),
            nativeMessagingPrerequisites: nativeMessagingPrerequisites(),
            storagePrerequisites: storagePrerequisites(),
            permissionsActiveTabPrerequisites: permissionsPrerequisites(),
            serviceWorkerLifecyclePrerequisites: lifecyclePrerequisites(),
            passwordManagerPrerequisiteSummary: passwordSummary(),
            unsupportedDeferredAPIs:
                ChromeMV3UnsupportedDeferredAPISummary(
                    unsupportedAPIs: [],
                    deferredAPIs: [.nativeMessaging],
                    unsupportedDeferredAPIsRemainRuntimeBlockers: true
                ),
            modeledOnlyComponents: ["runtime messaging routes"],
            blockedComponents: ["runtime message dispatch"],
            requiredFutureComponents: ["runtime messaging dispatcher"],
            unsupportedOrDeferredAPIs: [.nativeMessaging],
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            contextCreationBlockedReason:
                "Context creation remains blocked.",
            contextLoadingBlockedReason:
                "Context loading remains blocked.",
            runtimeLoadableFalseReason:
                "runtimeLoadable remains false.",
            nextRequiredCategoryAfterThisReport:
                .implementRuntimeBridgeComponents,
            documentationSources: [],
            warnings: []
        )
    }

    private func manifestFacts(
        rootPath: String
    ) -> ChromeMV3RuntimeBridgeManifestFacts {
        ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: .loaded,
            manifestPath:
                URL(fileURLWithPath: rootPath)
                .appendingPathComponent("manifest.json")
                .path,
            manifestSHA256: String(repeating: "b", count: 64),
            declaredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: ["history"],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            contentScriptsPresent: true,
            contentScriptMatchPatterns: ["https://example.com/*"],
            actionPopupPresent: true,
            backgroundServiceWorkerPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            activeTabPermissionPresent: false,
            permissionsAPIPresent: true,
            warnings: []
        )
    }

    private func runtimeMessagingPrerequisites()
        -> ChromeMV3RuntimeMessagingContract
    {
        ChromeMV3RuntimeMessagingContract(
            status: .modeled,
            implementedNow: false,
            dispatchImplemented: false,
            listenerDeliveryImplemented: false,
            callbackCompatibilityRequired: true,
            promiseCompatibilityRequired: true,
            lastErrorRequirement:
                "Chrome-style lastError contract required.",
            timeoutPolicyRequired: true,
            timeoutPolicy: "No runtime schedule in this layer.",
            routes: [
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "contentScriptToServiceWorker",
                    requiredAPI: "runtime.sendMessage",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "extensionPageOrPopupToServiceWorker",
                    requiredAPI: "runtime.sendMessage",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: false,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "serviceWorkerToTabContentScript",
                    requiredAPI: "tabs.sendMessage",
                    requiresServiceWorkerWakePolicy: false,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "contentScriptLongLivedPortToExtension",
                    requiredAPI: "runtime.connect",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
            ],
            portLifecycleRequirements: ["Port model required."],
            disconnectReasons: ["tabClosed"],
            contentScriptMessagingRestrictions: [
                "Content scripts message extension contexts.",
            ],
            requiredBeforePasswordManagerSupport: true,
            requiredBeforeRuntimeLoadability: true,
            blockers: ["Runtime messaging is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func nativeMessagingPrerequisites()
        -> ChromeMV3NativeMessagingPrerequisites
    {
        ChromeMV3NativeMessagingPrerequisites(
            status: .blocked,
            nativeMessagingDetected: true,
            nativeMessagingBlocked: true,
            hostManifestLookupImplemented: true,
            hostValidationImplemented: true,
            userConsentImplemented: false,
            processLaunchImplemented: false,
            stdioFramingRequired: true,
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 67_108_864,
            portLifecycleModeled: true,
            hostExitBehaviorModeled: true,
            disabledModuleBehavior: "No native messaging runtime.",
            noLaunchWhileExtensionsDisabled: true,
            noLaunchBeforeExplicitImplementation: true,
            requiredBeforePasswordManagerSupport: true,
            futureSecurityReviewRequired: true,
            blockers: ["Native messaging remains blocked."],
            hostManifestLookupRequirements: [],
            allowedHostValidationRequirements: [],
            futureTestsNeeded: []
        )
    }

    private func storagePrerequisites() -> ChromeMV3StoragePrerequisites {
        ChromeMV3StoragePrerequisites(
            status: .notImplemented,
            storagePermissionPresent: true,
            implementedNow: false,
            webKitBehaviorSufficientWithoutHostLayer: false,
            hostBackedLayerDecisionRequired: true,
            profileIsolationVerified: false,
            workerUnloadReloadStateVerified: false,
            passwordManagerStateRequirements: [
                "Password-manager state required.",
            ],
            areas: ChromeMV3StorageAreaName.allCases.map {
                ChromeMV3StorageAreaPrerequisite(
                    area: $0,
                    required: true,
                    implementedNow: false,
                    persistenceExpectation: "Modeled.",
                    contentScriptExposureDefault: "Modeled.",
                    decisionRequired: "Future decision required.",
                    blockers: ["Storage is not implemented."]
                )
            },
            blockers: ["Storage is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func permissionsPrerequisites()
        -> ChromeMV3PermissionsActiveTabPrerequisites
    {
        ChromeMV3PermissionsActiveTabPrerequisites(
            status: .notImplemented,
            requiredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: ["history"],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            activeTabDeclared: false,
            permissionBrokerImplemented: true,
            activeTabImplemented: true,
            hostPermissionEvaluationImplemented: true,
            userGestureRequirementModeled: true,
            grantLifetimeRequirement: "Modeled.",
            tabNavigationInvalidationRequirement: "Modeled.",
            permissionPromptUIFutureRequirement: true,
            contentScriptExecutionInteraction: "Blocked.",
            passwordManagerHostAccessRequirement: "Required.",
            requiredBeforeContentScriptExecution: true,
            requiredBeforePasswordManagerSupport: true,
            blockers: ["Real permission prompts are not implemented."],
            futureTestsNeeded: []
        )
    }

    private func lifecyclePrerequisites()
        -> ChromeMV3ServiceWorkerLifecycleReadiness
    {
        ChromeMV3ServiceWorkerLifecycleReadiness(
            status: .notImplemented,
            lifecycleCoordinatorImplemented: false,
            serviceWorkerWakeImplemented: false,
            idleUnloadPolicyModeled: true,
            permanentBackgroundForbidden: true,
            requiredBeforeContextLoad: true,
            requiredBeforeContextLoadReason: "Required.",
            requiredBeforeRuntimeLoadability: true,
            wakeReasonsRequired: ["runtime message"],
            eventDispatchPrerequisites: ["message dispatch"],
            idleReleasePolicy: "Modeled.",
            hardTimeoutPolicy: "Modeled.",
            longLivedPortPolicy: "Modeled.",
            nativeMessagingPortPolicy: "Blocked.",
            alarmWakePolicy: "Modeled.",
            statePersistenceRequirements: [],
            diagnosticsRequired: [],
            blockers: ["Service-worker wake is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func passwordSummary()
        -> ChromeMV3PasswordManagerPrerequisiteSummary
    {
        ChromeMV3PasswordManagerPrerequisiteSummary(
            contentScriptsPresent: true,
            actionPopupPresent: true,
            hostPermissionsPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            runtimeMessagingMissing: true,
            permissionActiveTabMissing: true,
            storageBackendMissingOrDeferred: true,
            nativeMessagingMissing: true,
            controlledInputPageWorldBehaviorNotVerified: true,
            serviceWorkerLifecycleNotVerified: true,
            passwordManagerSupportReady: false,
            blockers: ["Password-manager messaging is not ready."],
            deferredChecks: []
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private struct SourceFile {
        var relativePath: String
        var contents: String
    }

    private static func sourceFiles(
        in roots: [String]
    ) throws -> [SourceFile] {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var files: [SourceFile] = []
        for root in roots {
            let directory = rootURL.appendingPathComponent(root)
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator
            where url.pathExtension == "swift" {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey]
                )
                guard values.isRegularFile == true else { continue }
                files.append(
                    SourceFile(
                        relativePath:
                            url.path.replacingOccurrences(
                                of: rootURL.path + "/",
                                with: ""
                            ),
                        contents: try String(contentsOf: url, encoding: .utf8)
                    )
                )
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
}
