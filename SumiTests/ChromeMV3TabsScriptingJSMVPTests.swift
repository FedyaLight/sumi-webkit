import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3TabsScriptingJSMVPTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testShimSourceExposesRuntimeTabsAndScriptingOnly() {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let source = ChromeMV3TabsScriptingJSShimSource.source(
            configuration: configuration
        )
        let coverage = ChromeMV3TabsScriptingJSShimSource.coverage
        let runtimeOnlySource = ChromeMV3RuntimeJSShimSource.source(
            configuration: .syntheticHarness()
        )

        XCTAssertEqual(
            coverage.exposedChromeNamespaces,
            ["runtime", "scripting", "tabs"]
        )
        XCTAssertEqual(coverage.tabsMethods.sorted(), [
            "connect",
            "query",
            "sendMessage",
        ])
        XCTAssertEqual(coverage.scriptingMethods, ["executeScript"])
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"tabs\""))
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"scripting\""))
        XCTAssertTrue(source.contains("Object.defineProperty(runtime, \"lastError\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"storage\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"permissions\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"nativeMessaging\""))

        XCTAssertFalse(runtimeOnlySource.contains("Object.defineProperty(chromeObject, \"tabs\""))
        XCTAssertFalse(runtimeOnlySource.contains("Object.defineProperty(chromeObject, \"scripting\""))
    }

    func testSyntheticTabRegistryQueryReturnsOnlyControlledSyntheticTabs() {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let registry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: true
            )
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registry
        )

        let response = handler.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object([:])]
            )
        )

        XCTAssertTrue(response.succeeded)
        let tabs = array(response.resultPayload)
        XCTAssertEqual(tabs?.count, 1)
        XCTAssertEqual(object(tabs?.first)?["id"], .number(1))
        XCTAssertEqual(
            response.tabRegistrySummary.productNormalTabCount,
            1
        )
        XCTAssertTrue(
            response.tabRegistrySummary.productNormalTabsExcludedFromQuery
        )
        XCTAssertFalse(
            response.tabRegistrySummary.mutatesRealTabManagerState
        )
        XCTAssertFalse(response.tabRegistrySummary.startsBackgroundObservers)
    }

    func testTabsQueryRedactsAndExposesSensitiveFieldsByPermission() {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let redactedHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let hostHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.hostAndScripting(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let activeTabHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.activeTabGrant(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )

        let redacted = redactedHandler.handle(queryRequest())
        let host = hostHandler.handle(queryRequest())
        let activeTab = activeTabHandler.handle(queryRequest())

        XCTAssertTrue(redacted.succeeded)
        XCTAssertNil(object(array(redacted.resultPayload)?.first)?["url"])
        XCTAssertNil(object(array(redacted.resultPayload)?.first)?["title"])
        XCTAssertEqual(
            redacted.tabRegistrySummary.controlledSyntheticTabCount,
            1
        )

        XCTAssertEqual(
            object(array(host.resultPayload)?.first)?["url"],
            .string("https://example.com/login")
        )
        XCTAssertEqual(
            object(array(host.resultPayload)?.first)?["title"],
            .string("Example Login")
        )

        XCTAssertEqual(
            object(array(activeTab.resultPayload)?.first)?["url"],
            .string("https://example.com/login")
        )
    }

    func testTabsSendMessageErrorsAndContentScriptEndpointResponse() {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration
        )
        let noPermissionHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let missingEndpointHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: missingEndpointRegistry(configuration: configuration)
        )

        let missingTab = handler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [.number(404), .object(["type": .string("ping")])]
            )
        )
        let noPermission = noPermissionHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .callback,
                arguments: [.number(1), .object(["type": .string("ping")])]
            )
        )
        let noReceiver = missingEndpointHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .callback,
                arguments: [
                    .number(7),
                    .object(["type": .string("ping")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )
        let delivered = handler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("fill")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )

        XCTAssertFalse(missingTab.succeeded)
        XCTAssertEqual(
            missingTab.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.targetTabMissing.rawValue
        )
        XCTAssertTrue(missingTab.promiseWouldReject)

        XCTAssertFalse(noPermission.succeeded)
        XCTAssertEqual(
            noPermission.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.activeTabMissing.rawValue
        )
        XCTAssertTrue(noPermission.callbackWouldSetLastError)

        XCTAssertFalse(noReceiver.succeeded)
        XCTAssertEqual(
            noReceiver.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.noReceivingEnd.rawValue,
            noReceiver.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(noReceiver.callbackWouldSetLastError)

        XCTAssertTrue(delivered.succeeded)
        XCTAssertEqual(
            delivered.runtimeDispatcherResult?.routeKind,
            .tabsSendMessage
        )
        XCTAssertEqual(
            delivered.runtimeDispatcherResult?.modelHandlerInvoked,
            true
        )
        XCTAssertEqual(
            object(delivered.resultPayload)?["target"],
            .string("syntheticContentScriptModel")
        )
    }

    func testTabsConnectCreatesOnlySyntheticModelPort() {
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: .syntheticHarness()
        )

        let connect = handler.handle(
            request(
                namespace: "tabs",
                methodName: "connect",
                invocationMode: .fireAndForget,
                arguments: [
                    .number(1),
                    .object([
                        "name": .string("content"),
                        "frameId": .number(0),
                    ]),
                ]
            )
        )
        let postMessage = handler.handle(
            portRequest(
                "Port.postMessage",
                portID: "tabs-port",
                arguments: [.object(["type": .string("port")])]
            )
        )
        let disconnect = handler.handle(
            portRequest("Port.disconnect", portID: "tabs-port")
        )

        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(handler.modelPortCreateCount, 1)
        XCTAssertNotNil(connect.runtimeDispatcherResult?.modelPortPreflight)
        XCTAssertEqual(
            connect.runtimeDispatcherResult?
                .modelPortPreflight?
                .canOpenRuntimePortNow,
            false
        )
        XCTAssertEqual(
            object(connect.resultPayload)?["modelPortCreated"],
            .bool(true)
        )
        XCTAssertTrue(postMessage.succeeded)
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertFalse(connect.nativeMessagingAvailable)
        XCTAssertFalse(connect.serviceWorkerWakeAvailable)
        XCTAssertFalse(connect.runtimeLoadable)
    }

    func testLimitedScriptingExecuteScriptSuccessAndBlocks() {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let registry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: true
            )
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registry
        )
        let missingPermissionHandler =
            ChromeMV3TabsScriptingJSBridgeHandler(
                configuration: configuration,
                permissionBroker:
                    ChromeMV3TabsScriptingPermissionFixtures.hostOnly(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    )
            )

        let missingPermission = missingPermissionHandler.handle(
            executeScriptRequest(tabID: 1, invocationMode: .callback)
        )
        let productBlocked = handler.handle(
            executeScriptRequest(tabID: 99, invocationMode: .promise)
        )
        let success = handler.handle(
            executeScriptRequest(tabID: 1, invocationMode: .promise)
        )

        XCTAssertFalse(missingPermission.succeeded)
        XCTAssertEqual(
            missingPermission.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.permissionDenied.rawValue
        )
        XCTAssertTrue(missingPermission.callbackWouldSetLastError)

        XCTAssertFalse(productBlocked.succeeded)
        XCTAssertEqual(
            productBlocked.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.unsupportedAPI.rawValue
        )
        XCTAssertTrue(productBlocked.promiseWouldReject)

        XCTAssertTrue(success.succeeded)
        let result = object(array(success.resultPayload)?.first)
        XCTAssertEqual(result?["frameId"], .number(0))
        XCTAssertEqual(
            object(result?["result"])?["source"],
            .string("controlledSyntheticModel")
        )
        XCTAssertEqual(
            success.contentScriptEndpointSummary
                .dynamicExecuteScriptEndpointCount,
            1
        )
        XCTAssertFalse(success.scriptingAvailableInProduct)
        XCTAssertFalse(success.normalTabRuntimeBridgeAvailable)
    }

    @MainActor
    func testReportWriterDisabledModuleAndProfileDiagnostics() async throws {
        guard #available(macOS 15.5, *) else { return }
        let root = try temporaryDirectory(named: "tabs-scripting-report")
        let disabled = try makeModule(enabled: false)
        let disabledReport =
            disabled.chromeMV3TabsScriptingMVPReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        let disabledWebKitReport =
            await disabled
            .chromeMV3TabsScriptingWebKitSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertNil(disabledWebKitReport)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3TabsScriptingMVPReportWriter.reportFileName
                    ).path
            )
        )

        let enabled = try makeModule(enabled: true)
        let report = try XCTUnwrap(
            enabled.chromeMV3TabsScriptingMVPReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3TabsScriptingMVPReportWriter.reportFileName
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3TabsScriptingMVPReport.self,
            from: Data(contentsOf: reportURL)
        )
        let diagnostics = enabled.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertEqual(decoded.id, report.id)
        XCTAssertTrue(decoded.tabsJSBridgeAvailableInSyntheticHarness)
        XCTAssertFalse(decoded.tabsJSBridgeAvailableInProduct)
        XCTAssertFalse(decoded.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(decoded.scriptingAvailableInProduct)
        XCTAssertFalse(decoded.nativeMessagingAvailable)
        XCTAssertFalse(decoded.serviceWorkerWakeAvailable)
        XCTAssertFalse(decoded.runtimeLoadable)
        XCTAssertFalse(decoded.productRuntimeExposed)
        XCTAssertEqual(diagnostics?.tabsScriptingMVPReport?.id, report.id)

        let maybeWebKitReport =
            await enabled
            .chromeMV3TabsScriptingWebKitSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        let webKitReport = try XCTUnwrap(maybeWebKitReport)
        let webKitDecoded = try JSONDecoder().decode(
            ChromeMV3TabsScriptingMVPReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(webKitDecoded.id, webKitReport.id)
        XCTAssertTrue(
            webKitDecoded.webKitExecutionSummary
                .tabsScriptingJSExecutedInWebKitSyntheticHarness
        )
        XCTAssertTrue(
            webKitDecoded.summary
                .tabsScriptingJSExecutedInWebKitSyntheticHarness
        )
    }

    func testReportIsDeterministicAndCoversRequiredMVPFields() throws {
        let first = ChromeMV3TabsScriptingMVPReportGenerator.makeReport()
        let second = ChromeMV3TabsScriptingMVPReportGenerator.makeReport()

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(first),
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
        XCTAssertTrue(first.behaviorSummary.tabsQueryPromiseModeCovered)
        XCTAssertTrue(first.behaviorSummary.tabsScriptingModelHandlersAvailable)
        XCTAssertTrue(first.behaviorSummary.tabsSendMessageRoutesToDispatcher)
        XCTAssertTrue(first.behaviorSummary.tabsConnectCreatesModelPort)
        XCTAssertTrue(first.behaviorSummary.scriptingExecuteScriptModeled)
        XCTAssertTrue(first.behaviorSummary.scriptingProductTargetBlocked)
        XCTAssertTrue(first.behaviorSummary.noNativeMessagingOpened)
        XCTAssertTrue(first.behaviorSummary.noServiceWorkerWake)
        XCTAssertFalse(first.tabsJSBridgeAvailableInProduct)
        XCTAssertFalse(first.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(first.scriptingAvailableInProduct)
        XCTAssertFalse(first.runtimeLoadable)
        XCTAssertTrue(first.summary.tabsScriptingModelHandlersAvailable)
        XCTAssertTrue(
            first.summary.tabsScriptingJSBridgeAvailableInSyntheticHarness
        )
        XCTAssertFalse(
            first.summary.tabsScriptingJSExecutedInWebKitSyntheticHarness
        )
        XCTAssertEqual(
            first.webKitExecutionSummary.status,
            "notAttemptedByModelReportGenerator"
        )
    }

    @MainActor
    func testWebKitSyntheticHarnessExercisesTabsScriptingCalls()
        async throws
    {
        guard #available(macOS 15.5, *) else { return }
        let result = await ChromeMV3TabsScriptingJSSyntheticHarness.run(
            scriptBody:
                ChromeMV3TabsScriptingJSSyntheticHarness
                .reportVerificationScriptBody
        )

        XCTAssertTrue(
            result.scriptEvaluationSucceeded,
            result.diagnostics.joined(separator: "\n")
        )
        let object = try XCTUnwrap(
            try decodedObject(result.scriptResultJSON)
        )
        XCTAssertEqual(
            object["exposedNamespaces"] as? [String],
            ["runtime", "scripting", "tabs"]
        )
        XCTAssertEqual(object["storageMissing"] as? Bool, true)
        XCTAssertEqual(object["permissionsMissing"] as? Bool, true)
        XCTAssertEqual(object["nativeMessagingMissing"] as? Bool, true)
        XCTAssertEqual(object["tabsQueryCallbackOK"] as? Bool, true)
        XCTAssertEqual(object["tabsQueryPromiseOK"] as? Bool, true)
        XCTAssertEqual(
            object["tabsSendMessagePromiseOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["tabsSendMessageCallbackOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["tabsSendMessageNoReceiverLastErrorOK"] as? Bool,
            true
        )
        XCTAssertEqual(object["tabsConnectOK"] as? Bool, true)
        XCTAssertEqual(
            object["tabsConnectDisconnectOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["scriptingExecuteScriptOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["scriptingProductTargetBlockedOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["callbackLastErrorScopedOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["promiseRejectsOnErrorOK"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["noReceiverInside"] as? String,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertTrue(
            (object["noReceiverOutside"] as? NSNull) != nil
                || object["noReceiverOutside"] == nil
        )

        XCTAssertEqual(result.userScriptCount, 1)
        XCTAssertEqual(result.scriptMessageHandlerCount, 1)
        XCTAssertGreaterThanOrEqual(result.queryRequestCount, 2)
        XCTAssertGreaterThanOrEqual(result.sendMessageDispatchCount, 4)
        XCTAssertEqual(result.modelPortCreateCount, 1)
        XCTAssertEqual(result.modelPortDisconnectCount, 1)
        XCTAssertEqual(result.executeScriptRequestCount, 2)
        XCTAssertTrue(
            result.webKitExecutionSummary
                .tabsScriptingJSExecutedInWebKitSyntheticHarness
        )
        XCTAssertTrue(result.webKitExecutionSummary.tabsQueryCallbackExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.tabsQueryPromiseExecuted)
        XCTAssertTrue(
            result.webKitExecutionSummary
                .tabsSendMessageNoReceiverLastErrorExecuted
        )
        XCTAssertTrue(result.webKitExecutionSummary.tabsConnectExecuted)
        XCTAssertTrue(
            result.webKitExecutionSummary.scriptingExecuteScriptExecuted
        )
        XCTAssertTrue(
            result.webKitExecutionSummary.scriptingProductTargetBlocked
        )
        XCTAssertFalse(result.tabsJSBridgeAvailableInProduct)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.scriptingAvailableInProduct)
        XCTAssertFalse(result.runtimeLoadable)
        XCTAssertEqual(
            result.tabRegistrySummaryAfterTeardown
                .controlledSyntheticTabCount,
            0
        )
        XCTAssertEqual(
            result.contentScriptEndpointSummaryAfterTeardown.endpointCount,
            0
        )
        XCTAssertTrue(
            result.report.summary
                .tabsScriptingJSExecutedInWebKitSyntheticHarness
        )
    }

    @MainActor
    func testWebKitSyntheticHarnessTabsQueryPermissionRedactionAndActiveTab()
        async throws
    {
        guard #available(macOS 15.5, *) else { return }
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness()
        let redacted = await ChromeMV3TabsScriptingJSSyntheticHarness.run(
            scriptBody: """
            let callbackTabs = null;
            await new Promise((resolve) => {
              chrome.tabs.query({active: true}, function(tabs) {
                callbackTabs = tabs;
                resolve();
              });
            });
            const promiseTabs = await chrome.tabs.query({active: true});
            const redacted =
              Array.isArray(promiseTabs)
              && promiseTabs.length === 1
              && promiseTabs[0].url === undefined
              && promiseTabs[0].title === undefined;
            return {
              callbackTabs,
              promiseTabs,
              tabsQueryCallbackOK:
                Array.isArray(callbackTabs) && callbackTabs.length === 1,
              tabsQueryPromiseOK:
                Array.isArray(promiseTabs) && promiseTabs.length === 1,
              tabsQueryRedactionOK: redacted,
              callbackLastErrorScopedOK: chrome.runtime.lastError === undefined,
              promiseRejectsOnErrorOK: false
            };
            """,
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    includeProductNormalTab: true
                ),
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let activeTab = await ChromeMV3TabsScriptingJSSyntheticHarness.run(
            scriptBody: """
            const tabs = await chrome.tabs.query({active: true});
            return {
              tab: tabs[0] || null,
              tabsQueryPromiseOK:
                Array.isArray(tabs)
                && tabs.length === 1
                && tabs[0].url === "https://example.com/login"
                && tabs[0].title === "Example Login",
              tabsQueryRedactionOK:
                Array.isArray(tabs)
                && tabs.length === 1
                && tabs[0].url === "https://example.com/login"
            };
            """,
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    includeProductNormalTab: true
                ),
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.activeTabGrant(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )

        XCTAssertTrue(
            redacted.scriptEvaluationSucceeded,
            redacted.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(
            activeTab.scriptEvaluationSucceeded,
            activeTab.diagnostics.joined(separator: "\n")
        )
        let redactedObject = try XCTUnwrap(
            try decodedObject(redacted.scriptResultJSON)
        )
        let activeTabObject = try XCTUnwrap(
            try decodedObject(activeTab.scriptResultJSON)
        )

        XCTAssertEqual(redactedObject["tabsQueryCallbackOK"] as? Bool, true)
        XCTAssertEqual(redactedObject["tabsQueryPromiseOK"] as? Bool, true)
        XCTAssertEqual(redactedObject["tabsQueryRedactionOK"] as? Bool, true)
        XCTAssertTrue(
            redacted.webKitExecutionSummary.tabsQueryRedactionExecuted
        )
        XCTAssertEqual(activeTabObject["tabsQueryPromiseOK"] as? Bool, true)
        XCTAssertEqual(activeTabObject["tabsQueryRedactionOK"] as? Bool, true)
        XCTAssertTrue(
            activeTab.webKitExecutionSummary.tabsQueryPromiseExecuted
        )
    }

    func testTeardownClearsSyntheticTabAndEndpointState() {
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        XCTAssertEqual(
            handler.tabRegistry.summary.controlledSyntheticTabCount,
            1
        )

        handler.tearDown()

        XCTAssertEqual(
            handler.tabRegistry.summary.controlledSyntheticTabCount,
            0
        )
        XCTAssertEqual(
            handler.tabRegistry.contentScriptEndpointSummary.endpointCount,
            0
        )
    }

    func testSourceLevelGuardsForTabsScriptingMVP() throws {
        let sources = try sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let joined = sources.map(\.contents).joined(separator: "\n")
        let tabsSource = sources.first {
            $0.relativePath
                == "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
        }?.contents ?? ""
        let browserConfigSource = try String(
            contentsOf:
                URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Models/BrowserConfig/BrowserConfig.swift"
                ),
            encoding: .utf8
        )
        let tabsHarnessAllowlist: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
            "SumiTests/ChromeMV3TabsScriptingJSMVPTests.swift",
        ]
        let otherChromeMV3Joined = sources
            .filter { tabsHarnessAllowlist.contains($0.relativePath) == false }
            .map(\.contents)
            .joined(separator: "\n")

        XCTAssertTrue(tabsSource.contains("add" + "ScriptMessageHandler"))
        XCTAssertTrue(tabsSource.contains("WKUser" + "Script("))
        XCTAssertTrue(tabsSource.contains("addUser" + "Script"))
        XCTAssertFalse(
            otherChromeMV3Joined.contains(
                ChromeMV3TabsScriptingJSShimSource.bridgeMessageHandlerName
            )
        )
        XCTAssertFalse(
            browserConfigSource.contains(
                ChromeMV3TabsScriptingJSShimSource.bridgeMessageHandlerName
            )
        )
        XCTAssertFalse(
            browserConfigSource.contains("ChromeMV3TabsScriptingJSShimSource")
        )
        for forbidden in [
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }
        for forbiddenRegex in [
            "runtime" + "Loadable.*" + "tr" + "ue",
            "tabsJSBridgeAvailableInProduct.*" + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable.*" + "tr" + "ue",
            "scriptingAvailableInProduct.*" + "tr" + "ue",
            "serviceWorkerWakeAvailable.*" + "tr" + "ue",
            "nativeMessagingAvailable.*" + "tr" + "ue",
            "productRuntimeExposed.*" + "tr" + "ue",
        ] {
            let regex = try NSRegularExpression(pattern: forbiddenRegex)
            let range = NSRange(joined.startIndex..., in: joined)
            XCTAssertNil(
                regex.firstMatch(in: joined, range: range),
                forbiddenRegex
            )
        }
    }

    private func queryRequest()
        -> ChromeMV3RuntimeJSBridgeHostRequest
    {
        request(
            namespace: "tabs",
            methodName: "query",
            invocationMode: .promise,
            arguments: [.object(["active": .bool(true)])]
        )
    }

    private func executeScriptRequest(
        tabID: Int,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "scripting",
            methodName: "executeScript",
            invocationMode: invocationMode,
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(Double(tabID)),
                        "frameIds": .array([.number(0)]),
                    ]),
                    "functionSource": .string("function getTitle() { return document.title; }"),
                    "args": .array([]),
                ]),
            ]
        )
    }

    private func missingEndpointRegistry(
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration
    ) -> ChromeMV3SyntheticTabRegistry {
        ChromeMV3SyntheticTabRegistry(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabs: [
                ChromeMV3SyntheticTabRecord(
                    id: 7,
                    profileID: configuration.profileID,
                    url: "https://example.com/no-listener",
                    title: "No Listener",
                    active: true,
                    frames: [
                        ChromeMV3SyntheticTabFrameRecord(
                            frameID: 0,
                            documentID: "document-no-listener",
                            url: "https://example.com/no-listener",
                            staticContentScriptEndpointRegistered: false,
                            connectEndpointRegistered: false
                        ),
                    ]
                ),
            ]
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func portRequest(
        _ methodName: String,
        portID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: "tabs",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: portID,
            diagnostics: []
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3TabsScriptingJSMVPTests.\(UUID().uuidString)"
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

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3TabsScriptingJSMVPTests",
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

    private func array(_ value: ChromeMV3StorageValue?)
        -> [ChromeMV3StorageValue]?
    {
        guard case .array(let values) = value else { return nil }
        return values
    }

    private func object(_ value: ChromeMV3StorageValue?)
        -> [String: ChromeMV3StorageValue]?
    {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func decodedObject(_ json: String?) throws -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func sourceFiles(
        in roots: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var results: [(String, String)] = []
        for relativeRoot in roots {
            let url = root.appendingPathComponent(relativeRoot)
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey]
                )
                guard values.isRegularFile == true else { continue }
                let relative = String(
                    file.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                results.append(
                    (
                        relative,
                        try String(contentsOf: file, encoding: .utf8)
                    )
                )
            }
        }
        return results
    }
}
