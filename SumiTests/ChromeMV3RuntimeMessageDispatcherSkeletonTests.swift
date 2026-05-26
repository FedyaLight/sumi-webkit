import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeMessageDispatcherSkeletonTests: XCTestCase {
    func testModelListenerRegistryStoresDeterministicEndpointSnapshot()
        throws
    {
        let first = serviceWorkerRegistry(response: .string("pong"))
        let second = ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: first.endpoints.reversed()
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.summary.endpointCount, 1)
        XCTAssertEqual(first.summary.endpointKinds, [.serviceWorkerModel])
        XCTAssertEqual(
            first.summary.listenerSurfaces,
            [.runtimeOnMessageServiceWorker]
        )
        XCTAssertTrue(first.summary.endpointsCanReceiveModelMessages)
        XCTAssertFalse(first.summary.endpointsCanReceiveRuntimeMessagesNow)
        let encoded = try ChromeMV3DeterministicJSON.encodedData(first)
        XCTAssertEqual(
            encoded,
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
    }

    func testDisabledModuleBlocksDispatcherModelDispatch() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("pong")),
            moduleState: .disabled
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertFalse(result.acceptedByPreflight)
        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertEqual(result.selectedLastError?.error, .extensionDisabled)
        XCTAssertFalse(result.canDispatchModelMessagesNow)
        XCTAssertFalse(result.canDispatchRuntimeMessagesNow)
        XCTAssertFalse(result.runtimeLoadable)
    }

    func testRuntimeSendMessageModelRouteWithNoListenerMapsToNoReceivingEnd() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: .empty(extensionID: extensionID, profileID: profileID)
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertFalse(result.receivingEndpointFound)
        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertEqual(result.selectedLastError?.error, .noReceivingEnd)
        XCTAssertEqual(result.promiseBehavior, .wouldReject)
    }

    func testRuntimeSendMessageModelRouteWithListenerReturnsResponse() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("pong"))
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertTrue(result.acceptedByPreflight)
        XCTAssertTrue(result.receivingEndpointFound)
        XCTAssertTrue(result.modelHandlerInvoked)
        XCTAssertFalse(result.runtimeHandlerInvoked)
        XCTAssertEqual(result.responsePayload, .string("pong"))
        XCTAssertNil(result.selectedLastError)
        XCTAssertEqual(result.promiseBehavior, .wouldResolveWithResponse)
        XCTAssertTrue(result.canDispatchModelMessagesNow)
        XCTAssertFalse(result.canDispatchMessagesNow)
    }

    func testTabsSendMessageUsesPermissionBrokerAndListenerRegistry() {
        let route = messageRoute(
            .tabsSendMessage,
            targetURL: "https://example.com/login"
        )
        let input = dispatchInput(
            route: route,
            registry: contentScriptRegistry(response: .string("content-ok"))
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertTrue(result.permissionDecision.allowedForFutureDispatch)
        XCTAssertTrue(result.receivingEndpointFound)
        XCTAssertEqual(result.responsePayload, .string("content-ok"))
        XCTAssertEqual(
            result.selectedEndpoint?.endpointKind,
            .contentScriptModel
        )
    }

    func testMissingHostPermissionBlocksModelDispatchWithHostPermissionMissing()
    {
        let route = messageRoute(
            .tabsSendMessage,
            targetURL: "https://blocked.example/login"
        )
        let input = dispatchInput(
            route: route,
            registry: contentScriptRegistry(response: .string("content-ok")),
            permissionBroker: permissionBroker(hostPermissions: [])
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertEqual(result.selectedLastError?.error, .hostPermissionMissing)
        XCTAssertEqual(result.promiseBehavior, .wouldReject)
    }

    func testMissingActiveTabBlocksModelDispatchWithActiveTabMissing() {
        let route = messageRoute(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let input = dispatchInput(
            route: route,
            registry: contentScriptRegistry(response: .string("content-ok")),
            permissionBroker:
                permissionBroker(
                    requiredPermissions: ["activeTab"],
                    hostPermissions: []
                )
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertEqual(result.selectedLastError?.error, .activeTabMissing)
    }

    func testActionPopupToServiceWorkerBlocksWithoutModelWakeBypass() {
        let route = messageRoute(.actionPopupToServiceWorker)
        let blocked = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: dispatchInput(
                route: route,
                registry: serviceWorkerRegistry(
                    response: .string("popup-ok"),
                    bypassServiceWorkerWake: false
                )
            )
        )
        let bypassed = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: dispatchInput(
                route: route,
                registry: serviceWorkerRegistry(
                    response: .string("popup-ok"),
                    bypassServiceWorkerWake: true
                )
            )
        )

        XCTAssertEqual(
            blocked.selectedLastError?.error,
            .serviceWorkerUnavailable
        )
        XCTAssertFalse(blocked.modelHandlerInvoked)
        XCTAssertNil(bypassed.selectedLastError)
        XCTAssertEqual(bypassed.responsePayload, .string("popup-ok"))
        XCTAssertTrue(bypassed.modelHandlerInvoked)
        XCTAssertFalse(bypassed.canWakeServiceWorkerNow)
    }

    func testContentScriptToServiceWorkerReturnsDeterministicModelResponse() {
        let route = messageRoute(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("worker-ok"))
        )

        let first = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)
        let second = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.modelHandlerInvoked)
        XCTAssertEqual(first.responsePayload, .string("worker-ok"))
        XCTAssertTrue(first.canDispatchModelMessagesNow)
    }

    func testServiceWorkerToTabChecksPermissionAndListenerEndpoint() {
        let route = messageRoute(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let missing = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: dispatchInput(
                route: route,
                registry: .empty(extensionID: extensionID, profileID: profileID)
            )
        )
        let delivered = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: dispatchInput(
                route: route,
                registry: contentScriptRegistry(response: .string("tab-ok"))
            )
        )

        XCTAssertEqual(missing.selectedLastError?.error, .noReceivingEnd)
        XCTAssertNil(delivered.selectedLastError)
        XCTAssertEqual(delivered.responsePayload, .string("tab-ok"))
        XCTAssertEqual(
            delivered.selectedEndpoint?.listenerSurface.surface,
            .tabsMessageContentScript
        )
    }

    func testContextNotLoadedMapsToLastErrorWhenRuntimeRequested() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("pong")),
            dispatchMode: .runtimeRequestedButBlocked
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertEqual(result.selectedLastError?.error, .contextNotLoaded)
        XCTAssertEqual(result.promiseBehavior, .wouldReject)
    }

    func testCallbackModeResultIsDeterministic() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("pong")),
            responseMode: .callback
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertEqual(result.callbackBehavior, .wouldInvokeWithResponse)
        XCTAssertEqual(result.promiseBehavior, .notRequested)
        XCTAssertEqual(result.responsePayload, .string("pong"))
    }

    func testPromiseModeResultIsDeterministic() {
        let route = messageRoute(.runtimeSendMessage)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("pong")),
            responseMode: .promise
        )

        let first = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)
        let second = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.promiseBehavior, .wouldResolveWithResponse)
        XCTAssertEqual(first.callbackBehavior, .noCallbackRequested)
    }

    func testConnectRouteReturnsPortPreflightButOpensNoPort() {
        let route = messageRoute(.runtimeConnect)
        let input = dispatchInput(
            route: route,
            registry: serviceWorkerRegistry(response: .string("unused")),
            responseMode: .callback,
            payloadClassification: .portConnectionRequest
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)
        let preflight = result.modelPortPreflight

        XCTAssertTrue(preflight?.modelPortPreflightEvaluated ?? false)
        XCTAssertFalse(result.modelHandlerInvoked)
        XCTAssertFalse(preflight?.canOpenRuntimePortNow ?? true)
        XCTAssertFalse(preflight?.canOpenNativePortNow ?? true)
        XCTAssertFalse(result.canOpenPortNow)
        XCTAssertEqual(result.selectedLastError?.error, .routeNotImplemented)
    }

    func testNativeMessagingConnectRemainsBlocked() {
        let route = messageRoute(.nativeMessaging)
        let input = dispatchInput(
            route: route,
            registry: nativeBlockedRegistry(),
            permissionBroker:
                permissionBroker(requiredPermissions: ["nativeMessaging"]),
            payloadClassification: .portConnectionRequest
        )

        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)

        XCTAssertEqual(result.selectedLastError?.error, .nativeMessagingBlocked)
        XCTAssertTrue(result.modelPortPreflight?.modelPortPreflightEvaluated ?? false)
        XCTAssertFalse(result.modelPortPreflight?.canOpenNativePortNow ?? true)
        XCTAssertNotNil(result.modelPortPreflight?.nativeMessagingPreflight)
    }

    func testPasswordManagerLikeFixtureReportsModelCoverageButRuntimeBlocked()
        throws
    {
        let report =
            ChromeMV3RuntimeMessageDispatcherSkeletonReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let password = report.passwordManagerMessagingFlowSummary

        XCTAssertTrue(
            password.contentScriptToServiceWorkerModelRouteCovered
        )
        XCTAssertTrue(password.popupToServiceWorkerModelRouteCovered)
        XCTAssertTrue(password.serviceWorkerToTabContentModelRouteCovered)
        XCTAssertTrue(password.portConnectModelPreflightCovered)
        XCTAssertTrue(password.nativeMessagingConnectBlocked)
        XCTAssertTrue(password.jsBridgeMissing)
        XCTAssertTrue(password.realListenerRegistrationMissing)
        XCTAssertTrue(password.serviceWorkerWakeMissing)
        XCTAssertTrue(password.passwordManagerModelMessagingReady)
        XCTAssertFalse(password.passwordManagerRuntimeMessagingReady)
        XCTAssertTrue(report.modelOnlyDispatchAvailable)
        XCTAssertFalse(report.runtimeDispatchAvailable)
        XCTAssertFalse(report.jsBridgeAvailable)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canOpenPortNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testDispatcherSkeletonReportIsDeterministicAndWritable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report =
            ChromeMV3RuntimeMessageDispatcherSkeletonReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter.reportFileName
        )

        try ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter
                .reportFileName
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3RuntimeMessageDispatcherSkeletonReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testSumiExtensionsModuleWritesDispatcherReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter
                .reportFileName
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

        let disabledReport =
            disabledModule
            .chromeMV3RuntimeMessageDispatcherSkeletonReportIfEnabled(
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
            enabledModule
                .chromeMV3RuntimeMessageDispatcherSkeletonReportIfEnabled(
                    fromRewrittenBundleRoot: root,
                    writeReport: true
                )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.runtimeMessageDispatcherSkeletonReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testRuntimeBridgeReadinessIncludesDispatcherSummary() {
        let report = ChromeMV3RuntimeBridgeReadinessReportGenerator
            .makeReport(
                prerequisitesReport: makePrerequisitesReport(),
                prerequisitesReportPath:
                    "/tmp/password-manager-fixture/runtime-bridge-prerequisites-report.json"
            )

        XCTAssertEqual(
            report.runtimeMessageDispatcherSkeletonReportSummary?
                .reportFileName,
            ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter
                .reportFileName
        )
        XCTAssertTrue(
            report.runtimeMessageDispatcherSkeletonReportSummary?
                .modelOnlyDispatchAvailable ?? false
        )
        let runtimeAvailable =
            report.runtimeMessageDispatcherSkeletonReportSummary?
            .runtimeDispatchAvailable ?? false
        XCTAssertFalse(
            runtimeAvailable
        )
    }

    func testSourceLevelGuardsForDispatcherSkeletonLayer() throws {
        let sources = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let joined = sources.map(\.contents).joined(separator: "\n")
        let boundaryGuardJoined = sources
            .filter {
                $0.relativePath
                    != "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift"
            }
            .map(\.contents)
            .joined(separator: "\n")

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(boundaryGuardJoined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "runtime" + "DispatchAvailable\\s*[:=].*" + "tr" + "ue",
            "js" + "BridgeAvailable\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canWake" + "ServiceWorkerNow\\s*[:=].*" + "tr" + "ue",
            "canOpen" + "PortNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerRuntimeMessagingReady\\s*[:=].*" + "tr" + "ue",
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

    private func messageRoute(
        _ kind: ChromeMV3RuntimeMessagingRouteKind,
        sourceURL: String? = "https://example.com/login",
        targetURL: String? = "https://example.com/login"
    ) -> ChromeMV3RuntimeMessagingRoute {
        ChromeMV3RuntimeMessagingRoute.make(
            kind: kind,
            extensionID: extensionID,
            profileID: profileID,
            tabID: 42,
            frameID: 0,
            documentID: "document-0",
            sourceURL: sourceURL,
            targetURL: targetURL
        )
    }

    private func dispatchInput(
        route: ChromeMV3RuntimeMessagingRoute,
        registry: ChromeMV3RuntimeModelListenerRegistrySnapshot,
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        dispatchMode: ChromeMV3RuntimeMessageDispatcherMode = .modelOnly,
        responseMode: ChromeMV3RuntimeMessagingResponseMode = .promise,
        payloadClassification:
            ChromeMV3RuntimeMessagingPayloadClassification = .jsonLike
    ) -> ChromeMV3RuntimeMessageDispatcherInput {
        let broker = permissionBroker
            ?? self.permissionBroker(
                requiredPermissions: [],
                hostPermissions: ["https://example.com/*"]
            )
        let permission = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: broker
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            payloadClassification: payloadClassification,
            responseMode: responseMode,
            permissionDecision: permission,
            seed: "dispatcher-test-\(route.kind.rawValue)"
        )
        return ChromeMV3RuntimeMessageDispatcherInput(
            route: route,
            messageEnvelope: envelope,
            listenerRegistrySnapshot: registry,
            permissionBrokerSnapshot: broker,
            serviceWorkerLifecycleSnapshot: .blocked(
                extensionID: route.extensionID,
                profileID: route.profileID
            ),
            moduleState: moduleState,
            dispatchMode: dispatchMode,
            userGestureAvailable: false,
            nativeHostName: "com.example.password_manager"
        )
    }

    private func serviceWorkerRegistry(
        response: ChromeMV3StorageValue,
        bypassServiceWorkerWake: Bool = true
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        let surface = ChromeMV3RuntimeListenerSurface.make(
            surface: .runtimeOnMessageServiceWorker,
            extensionID: extensionID,
            profileID: profileID
        )
        let endpoint = ChromeMV3RuntimeModelListenerEndpoint.make(
            surface: surface,
            endpointKind: .serviceWorkerModel,
            bypassesServiceWorkerWakeForModelOnlyDispatch:
                bypassServiceWorkerWake,
            handlerOutcome: .response(response)
        )
        return .make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: [endpoint]
        )
    }

    private func contentScriptRegistry(
        response: ChromeMV3StorageValue
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        let surface = ChromeMV3RuntimeListenerSurface.make(
            surface: .tabsMessageContentScript,
            extensionID: extensionID,
            profileID: profileID,
            tabID: 42,
            frameID: 0
        )
        let endpoint = ChromeMV3RuntimeModelListenerEndpoint.make(
            surface: surface,
            endpointKind: .contentScriptModel,
            handlerOutcome: .response(response)
        )
        return .make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: [endpoint]
        )
    }

    private func nativeBlockedRegistry()
        -> ChromeMV3RuntimeModelListenerRegistrySnapshot
    {
        let surface = ChromeMV3RuntimeListenerSurface.make(
            surface: .nativeMessagingPortListener,
            extensionID: extensionID,
            profileID: profileID
        )
        let endpoint = ChromeMV3RuntimeModelListenerEndpoint.make(
            surface: surface,
            endpointKind: .nativeMessagingBlockedModel,
            canReceiveModelMessages: false,
            handlerOutcome: nil
        )
        return .make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: [endpoint]
        )
    }

    private func permissionBroker(
        requiredPermissions: [String] = [],
        hostPermissions: [String] = ["https://example.com/*"],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: requiredPermissions,
                hostPermissions: hostPermissions,
                activeTabGrants: activeTabGrants
            )
        )
    }

    private func makePrerequisitesReport()
        -> ChromeMV3RuntimeBridgePrerequisitesReport
    {
        ChromeMV3RuntimeBridgePrerequisitesReport(
            schemaVersion: 1,
            id: "runtime-prerequisites-test",
            reportFileName:
                ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName,
            candidateID: "password-manager-fixture",
            generatedRewrittenRootPath: "/tmp/password-manager-fixture",
            contextReadinessReportID: "context-readiness-test",
            contextReadinessReportPath:
                "/tmp/password-manager-fixture/context-readiness-report.json",
            contextReadinessReportHash: String(repeating: "a", count: 64),
            contextReadinessConsumerDiagnostic:
                ChromeMV3ContextReadinessReportConsumptionDiagnostic(
                    schemaVersion: 1,
                    reportFileName:
                        ChromeMV3ContextReadinessReportWriter.reportFileName,
                    reportPath:
                        "/tmp/password-manager-fixture/context-readiness-report.json",
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
            manifestFacts: manifestFacts(),
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

    private func manifestFacts()
        -> ChromeMV3RuntimeBridgeManifestFacts
    {
        ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: .loaded,
            manifestPath: "/tmp/password-manager-fixture/manifest.json",
            manifestSHA256: String(repeating: "b", count: 64),
            declaredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            contentScriptsPresent: true,
            contentScriptMatchPatterns: ["https://example.com/*"],
            actionPopupPresent: true,
            backgroundServiceWorkerPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            activeTabPermissionPresent: false,
            permissionsAPIPresent: false,
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
            optionalPermissions: [],
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

    private static func sourceFiles(
        in relativeDirectories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = projectRoot()
        var files: [(relativePath: String, contents: String)] = []
        for relativeDirectory in relativeDirectories {
            let directory = root.appendingPathComponent(
                relativeDirectory,
                isDirectory: true
            )
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else { continue }

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                ])
                guard values.isRegularFile == true,
                      url.pathExtension == "swift"
                else { continue }
                let relativePath = String(
                    url.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                files.append(
                    (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                )
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
