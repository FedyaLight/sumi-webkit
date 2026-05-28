import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeMessagingContractTests: XCTestCase {
    func testAllRequiredRouteKindsAreModeled() {
        let routes = ChromeMV3RuntimeMessagingRoute.allModeledRoutes(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertEqual(
            Set(routes.map(\.kind)),
            Set(ChromeMV3RuntimeMessagingRouteKind.allCases)
        )
        XCTAssertTrue(routes.allSatisfy { $0.implementedNow == false })
    }

    func testContentScriptToServiceWorkerRequiresWakeAndDoesNotDispatch() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let snapshot = permissionSnapshot(
            hostPermissions: ["https://example.com/*"]
        )
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: snapshot
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: snapshot,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: true,
                serviceWorkerLifecycleReady: false
            )
        )

        XCTAssertTrue(route.requiresServiceWorkerWake)
        XCTAssertTrue(route.requiresHostPermission)
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertFalse(evaluation.canWakeServiceWorkerNow)
        XCTAssertEqual(
            evaluation.errorContract?.error,
            .serviceWorkerUnavailable
        )
    }

    func testActionPopupToServiceWorkerIsModeledAndNonDispatchable() {
        let route = route(.actionPopupToServiceWorker)
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: true,
                serviceWorkerLifecycleReady: true
            )
        )

        XCTAssertEqual(route.source.context, .actionPopup)
        XCTAssertEqual(route.target.context, .serviceWorker)
        XCTAssertTrue(route.requiresServiceWorkerWake)
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertEqual(evaluation.errorContract?.error, .routeNotImplemented)
    }

    func testServiceWorkerToTabRequiresTargetAndPermissionDecision() {
        let missingTabRoute = ChromeMV3RuntimeMessagingRoute.make(
            kind: .serviceWorkerToTab,
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let missingTabEnvelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: missingTabRoute
        )
        let missingTabEvaluation =
            ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
                route: missingTabRoute,
                envelope: missingTabEnvelope,
                permissionSnapshot: .empty,
                readiness: readiness()
            )

        let route = route(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let permissionDecision =
            ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
                route: route,
                snapshot: .empty
            )

        XCTAssertEqual(
            missingTabEvaluation.errorContract?.error,
            .targetTabMissing
        )
        XCTAssertTrue(route.requiresTabPermission)
        XCTAssertTrue(route.requiresHostPermission)
        XCTAssertTrue(route.requiresActiveTab)
        XCTAssertFalse(permissionDecision.allowedForFutureDispatch)
    }

    func testTabsSendMessageEvaluatesTabAndFrameMetadata() {
        let route = route(
            .tabsSendMessage,
            frameID: 7,
            documentID: "document-7",
            targetURL: "https://example.com/form"
        )
        let snapshot = permissionSnapshot(
            hostPermissions: ["https://example.com/*"]
        )
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: snapshot
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )

        XCTAssertEqual(envelope.senderMetadata.tabID, 42)
        XCTAssertEqual(envelope.senderMetadata.frameID, 7)
        XCTAssertEqual(envelope.senderMetadata.documentID, "document-7")
        XCTAssertEqual(
            envelope.senderMetadata.urlExposureStatus,
            .exposed
        )
    }

    func testNativeMessagingRouteIsBlockedAndDeferred() {
        let route = route(.nativeMessaging)
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            payloadClassification: .nativeMessagingJSON
        )

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(contextLoaded: true)
        )

        XCTAssertTrue(route.requiresNativeMessaging)
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertEqual(evaluation.errorContract?.error, .nativeMessagingBlocked)
    }

    func testEnvelopeOutputIsDeterministic() {
        let route = route(.runtimeSendMessage)

        let first = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            responseMode: .callback,
            seed: "same-seed"
        )
        let second = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            responseMode: .callback,
            seed: "same-seed"
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.messageID.hasPrefix("message-"))
        XCTAssertTrue(first.diagnosticTraceID.hasPrefix("trace-"))
    }

    func testSenderURLAndOriginAreRedactedWhenPermissionIsMissing() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://secret.example/login"
        )
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: .empty
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )

        XCTAssertEqual(
            decision.missingGrantReason,
            .missingHostPermission
        )
        XCTAssertEqual(
            decision.senderMetadataRedaction,
            .redactURLAndOrigin
        )
        XCTAssertNil(envelope.senderMetadata.url)
        XCTAssertNil(envelope.senderMetadata.origin)
        XCTAssertEqual(envelope.senderMetadata.urlExposureStatus, .redacted)
    }

    func testModeledHostPermissionExposesMetadataButStillDoesNotDispatch() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let snapshot = permissionSnapshot(
            hostPermissions: ["https://example.com/*"]
        )
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: snapshot
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )
        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: snapshot,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: true,
                serviceWorkerLifecycleReady: true
            )
        )

        XCTAssertTrue(decision.allowedForFutureDispatch)
        XCTAssertEqual(envelope.senderMetadata.url, "https://example.com/login")
        XCTAssertEqual(envelope.senderMetadata.origin, "https://example.com")
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertEqual(evaluation.errorContract?.error, .routeNotImplemented)
    }

    func testMissingHostPermissionMapsToHostPermissionMissing() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(contextLoaded: true)
        )

        XCTAssertEqual(
            evaluation.errorContract?.error,
            .hostPermissionMissing
        )
    }

    func testMissingActiveTabMapsToActiveTabMissing() {
        let route = route(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let snapshot = ChromeMV3RuntimeMessagingPermissionSnapshot(
            grantedHostPermissions: [],
            optionalPermissions: [],
            optionalHostPermissions: [],
            tabPermissionGranted: false,
            activeTabPermissionDeclared: true,
            activeTabGrants: [],
            deniedPermissions: [],
            userGestureAvailable: false
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: snapshot,
            readiness: readiness(contextLoaded: true)
        )

        XCTAssertEqual(evaluation.errorContract?.error, .activeTabMissing)
    }

    func testContextNotLoadedMapsToContextNotLoaded() {
        let route = route(.extensionPageToServiceWorker)
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(contextLoaded: false)
        )

        XCTAssertEqual(evaluation.errorContract?.error, .contextNotLoaded)
    }

    func testNoReceivingEndMapsToNoReceivingEnd() {
        let route = route(.extensionPageToServiceWorker)
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: false,
                serviceWorkerLifecycleReady: true
            )
        )

        XCTAssertEqual(evaluation.errorContract?.error, .noReceivingEnd)
    }

    func testCallbackAndPromiseBehaviorIsRepresentedButNotImplemented() {
        let contract = ChromeMV3RuntimeLastErrorContract.contract(
            for: .noReceivingEnd
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route(.runtimeSendMessage),
            responseMode: .callback
        )

        XCTAssertEqual(contract.promiseBehavior, .wouldReject)
        XCTAssertEqual(
            contract.callbackBehavior,
            .wouldInvokeWithUndefinedAndSetLastError
        )
        XCTAssertEqual(envelope.responseMode, .callback)
    }

    func testPortLifecycleModelIsDeterministicAndOpensNoPort() {
        let route = route(.runtimeConnect)
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            payloadClassification: .portConnectionRequest
        )

        let first = ChromeMV3RuntimePortContract.model(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(contextLoaded: true)
        )
        let second = ChromeMV3RuntimePortContract.model(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: readiness(contextLoaded: true)
        )

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.canOpenPortNow)
        XCTAssertFalse(first.portLifecycleImplemented)
        XCTAssertEqual(
            Set(first.disconnectReasons),
            Set(ChromeMV3RuntimePortDisconnectReason.allCases)
        )
    }

    func testPasswordManagerLikeReportKeepsMessagingBlocked() {
        let report = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let password = report.passwordManagerMessagingSummary

        XCTAssertTrue(password.contentScriptToServiceWorkerRouteRequired)
        XCTAssertTrue(password.popupToServiceWorkerRouteRequired)
        XCTAssertTrue(password.serviceWorkerToTabContentRouteRequired)
        XCTAssertTrue(password.portLifecycleRequiredForUnlockFillFlow)
        XCTAssertTrue(password.hostPermissionRequired)
        XCTAssertTrue(password.activeTabMayBeRequiredDependingOnUserAction)
        XCTAssertTrue(password.nativeMessagingRouteDetectedButBlocked)
        XCTAssertFalse(password.controlledInputPageWorldBehaviorVerified)
        XCTAssertFalse(password.passwordManagerMessagingReady)
        XCTAssertFalse(report.canDispatchMessagesNow)
        XCTAssertFalse(report.canRegisterListenersNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canOpenPortNow)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testMessagingReportIsDeterministic() throws {
        let prerequisites = makePrerequisitesReport()

        let first = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: prerequisites)
        let second = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: prerequisites)
        let firstData = try ChromeMV3DeterministicJSON.encodedData(first)
        let secondData = try ChromeMV3DeterministicJSON.encodedData(second)

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            first.reportFileName,
            ChromeMV3RuntimeMessagingContractReportWriter.reportFileName
        )
    }

    func testMessagingContractReportWriterWritesExpectedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())

        try ChromeMV3RuntimeMessagingContractReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let reportURL = root.appendingPathComponent(
            ChromeMV3RuntimeMessagingContractReportWriter.reportFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let decoded = try JSONDecoder().decode(
            ChromeMV3RuntimeMessagingContractReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testSumiExtensionsModuleWritesMessagingContractReportOnlyWhenEnabled()
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
            ChromeMV3RuntimeMessagingContractReportWriter.reportFileName
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
            disabledModule.chromeMV3RuntimeMessagingContractReportIfEnabled(
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
            enabledModule.chromeMV3RuntimeMessagingContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.runtimeMessagingContractReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testSourceLevelGuardsForRuntimeMessagingContractLayer()
        throws
    {
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
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift"
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
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canDispatch" + "MessagesNow\\s*[:=].*" + "tr" + "ue",
            "canRegister" + "ListenersNow\\s*[:=].*" + "tr" + "ue",
            "canWake" + "ServiceWorkerNow\\s*[:=].*" + "tr" + "ue",
            "canOpen" + "PortNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerMessagingReady\\s*[:=].*" + "tr" + "ue",
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

    private func route(
        _ kind: ChromeMV3RuntimeMessagingRouteKind,
        frameID: Int? = 0,
        documentID: String? = "document-0",
        sourceURL: String? = nil,
        targetURL: String? = nil
    ) -> ChromeMV3RuntimeMessagingRoute {
        ChromeMV3RuntimeMessagingRoute.make(
            kind: kind,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            frameID: frameID,
            documentID: documentID,
            sourceURL: sourceURL,
            targetURL: targetURL
        )
    }

    private func readiness(
        contextLoaded: Bool = false,
        receiverListenerRegistered: Bool = false,
        serviceWorkerLifecycleReady: Bool = false,
        targetTabExists: Bool = true,
        targetFrameExists: Bool = true
    ) -> ChromeMV3RuntimeMessagingReadinessSnapshot {
        ChromeMV3RuntimeMessagingReadinessSnapshot(
            extensionModuleEnabled: true,
            contextLoaded: contextLoaded,
            targetTabExists: targetTabExists,
            targetFrameExists: targetFrameExists,
            receiverListenerRegistered: receiverListenerRegistered,
            serviceWorkerLifecycleReady: serviceWorkerLifecycleReady,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false
        )
    }

    private func permissionSnapshot(
        hostPermissions: [String]
    ) -> ChromeMV3RuntimeMessagingPermissionSnapshot {
        ChromeMV3RuntimeMessagingPermissionSnapshot(
            grantedHostPermissions: hostPermissions,
            optionalPermissions: [],
            optionalHostPermissions: [],
            tabPermissionGranted: false,
            activeTabPermissionDeclared: false,
            activeTabGrants: [],
            deniedPermissions: [],
            userGestureAvailable: false
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
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
            passwordManagerStateRequirements: [],
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
