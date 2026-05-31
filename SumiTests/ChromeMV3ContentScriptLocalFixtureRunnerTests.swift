import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ContentScriptLocalFixtureRunnerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testLocalOriginModelIsDeterministicAndLoopbackOnly() {
        let first = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: "runner-a",
            sameOriginPort: 45101,
            crossOriginPort: 45102
        )
        let second = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: "runner-a",
            sameOriginPort: 45101,
            crossOriginPort: 45102
        )
        let preferredA =
            ChromeMV3ContentScriptLocalOriginModel.preferredPorts(
                runnerID: "runner-a"
            )
        let preferredB =
            ChromeMV3ContentScriptLocalOriginModel.preferredPorts(
                runnerID: "runner-a"
            )

        XCTAssertEqual(first, second)
        XCTAssertEqual(preferredA.sameOrigin, preferredB.sameOrigin)
        XCTAssertEqual(preferredA.crossOrigin, preferredB.crossOrigin)
        XCTAssertEqual(first.sameOrigin.host, "127.0.0.1")
        XCTAssertEqual(first.crossOrigin.host, "127.0.0.1")
        XCTAssertTrue(first.sameOrigin.loopbackOnly)
        XCTAssertTrue(first.crossOrigin.loopbackOnly)
        XCTAssertEqual(first.manifestMatchPattern, "http://127.0.0.1/*")
        XCTAssertNotEqual(
            first.sameOrigin.originString,
            first.crossOrigin.originString
        )
    }

    func testRouteAndServingPlanAreDeterministicAndTestOnly() {
        let model = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: "runner-routes",
            sameOriginPort: 45201,
            crossOriginPort: 45202
        )
        let routes = ChromeMV3ContentScriptLocalFixtureRoutes.routes(
            originModel: model
        )
        let plan = ChromeMV3ContentScriptLocalFixtureRoutes.servingPlan(
            originModel: model
        )

        XCTAssertEqual(
            routes.map(\.frameID),
            ["about-blank", "blob", "cross-origin", "data", "same-origin", "top"]
        )
        XCTAssertTrue(plan.debugInternalOnly)
        XCTAssertTrue(plan.loopbackOnly)
        XCTAssertFalse(plan.externalNetworkUsed)
        XCTAssertFalse(plan.productServer)
        XCTAssertFalse(plan.recurringChecksUsed)
        XCTAssertFalse(plan.userVisibleWindowRequired)
        XCTAssertFalse(plan.productNormalTabRequired)
        XCTAssertEqual(
            routes.first { $0.frameID == "same-origin" }?.urlString,
            model.sameOriginFrameURLString
        )
        XCTAssertEqual(
            routes.first { $0.frameID == "cross-origin" }?.urlString,
            model.crossOriginFrameURLString
        )
    }

    func testMissingExplicitLocalFixtureFlagBlocksRunner() throws {
        let root = try makeLocalContentScriptRoot(
            named: "local-fixture-missing-flag"
        )
        let input = try localFixtureGateInput(
            rootURL: root,
            explicitInternalLocalFixtureRunnerAllowed: false
        )
        let decision = ChromeMV3ContentScriptLocalFixtureGate.evaluate(
            input: input
        )

        XCTAssertFalse(decision.canStartLocalFixtureRunnerNow)
        XCTAssertTrue(
            decision.blockers.contains(
                .explicitLocalFixtureRunnerNotAllowed
            )
        )
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertFalse(decision.chromeRuntimeAvailableNow)
        XCTAssertFalse(decision.jsBridgeAvailableNow)
        XCTAssertFalse(decision.productRuntimeExposed)
    }

    func testContextLoadUnavailableProducesDeterministicBlockedReport()
        throws
    {
        let root = try makeLocalContentScriptRoot(
            named: "local-fixture-context-unavailable",
            allFrames: true,
            matchAboutBlank: true,
            matchOriginAsFallback: true
        )
        let input = try localFixtureGateInput(
            rootURL: root,
            loadedContextAvailable: false
        )
        let decision = ChromeMV3ContentScriptLocalFixtureGate.evaluate(
            input: input
        )
        let preferred =
            ChromeMV3ContentScriptLocalOriginModel.preferredPorts(
                runnerID: input.runnerID.rawValue
            )
        let originModel = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: input.runnerID.rawValue,
            sameOriginPort: preferred.sameOrigin,
            crossOriginPort: preferred.crossOrigin
        )
        let cases = ChromeMV3ContentScriptLocalFixtureMatrix.makeCases(
            runnerID: input.runnerID,
            fixtureID: input.fixtureID,
            originModel: originModel,
            manifestSummary:
                input.contentScriptFixturePolicy.manifestSummary,
            blockedReason: .contextLoadUnavailable,
            observationStrategy: .none
        )
        let report =
            ChromeMV3ContentScriptLocalFixtureRunnerReportGenerator
            .makeReport(
                candidate: makeCandidate(rootURL: root),
                originModel: originModel,
                setupResult: .notAttempted(
                    originModel: originModel,
                    reason: .contextLoadUnavailable,
                    diagnostics: decision.blockingReasons
                ),
                gateDecision: decision,
                matrixCases: cases,
                observationStrategy: .none,
                testDOMInspection: .notAttempted,
                navigationCompletionState: "notStarted"
            )

        XCTAssertTrue(
            report.prerequisiteState.blockedByContextLoadUnavailable
        )
        XCTAssertEqual(
            report.nextRecommendedAction,
            .blockedByContextLoadUnavailable
        )
        XCTAssertFalse(report.localFixtureSetupResult.serverStarted)
        XCTAssertTrue(report.matrixCases.isEmpty == false)
        XCTAssertTrue(report.matrixCases.allSatisfy {
            $0.actualObservation == .blocked
        })
        XCTAssertTrue(report.blockedCaseIDs.contains {
            $0.contains("top")
        })
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.productRuntimeExposed)
        assertLocalFixtureRuntimeCountersStayUnavailable(report)
    }

    func testMatrixSeparatesExpectedEligibilityFromActualObservation()
        throws
    {
        let root = try makeLocalContentScriptRoot(
            named: "local-fixture-matrix",
            allFrames: true,
            matchAboutBlank: true,
            matchOriginAsFallback: true
        )
        let input = try localFixtureGateInput(rootURL: root)
        let model = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: input.runnerID.rawValue,
            sameOriginPort: 45301,
            crossOriginPort: 45302
        )
        let topSnapshot = ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
            frameID: "top",
            accessible: true,
            markerObserved: true,
            markerAttributeValue: "top",
            markerTokenValue:
                ChromeMV3ContentScriptSmokeFixturePolicy.markerToken,
            executionReadyState: "complete",
            pageWorldGlobalValue:
                ChromeMV3ContentScriptSmokeFixturePolicy.markerToken,
            evaluationTarget: "mainFrame",
            reason: nil
        )
        let cases = ChromeMV3ContentScriptLocalFixtureMatrix.makeCases(
            runnerID: input.runnerID,
            fixtureID: input.fixtureID,
            originModel: model,
            manifestSummary:
                input.contentScriptFixturePolicy.manifestSummary,
            snapshots: ["top": topSnapshot],
            observationStrategy: .testDOMInspection
        )

        let top = try XCTUnwrap(
            cases.first { $0.route.frameID == "top" }
        )
        let same = try XCTUnwrap(
            cases.first { $0.route.frameID == "same-origin" }
        )
        let cross = try XCTUnwrap(
            cases.first { $0.route.frameID == "cross-origin" }
        )
        let about = try XCTUnwrap(
            cases.first { $0.route.frameID == "about-blank" }
        )
        let data = try XCTUnwrap(
            cases.first { $0.route.frameID == "data" }
        )
        let blob = try XCTUnwrap(
            cases.first { $0.route.frameID == "blob" }
        )

        XCTAssertEqual(top.expectedEligibility, .eligible)
        XCTAssertEqual(top.actualObservation, .observed)
        XCTAssertEqual(same.expectedEligibility, .eligible)
        XCTAssertEqual(same.actualObservation, .unverified)
        XCTAssertEqual(cross.expectedEligibility, .eligible)
        XCTAssertEqual(cross.actualObservation, .unverified)
        XCTAssertEqual(about.expectedEligibility, .eligible)
        XCTAssertEqual(data.expectedEligibility, .eligible)
        XCTAssertEqual(blob.expectedEligibility, .eligible)
    }

    func testRunAtAndWorldProofDoNotOverclaimWithoutEvidence() {
        let missingRunAt =
            ChromeMV3ContentScriptLocalFixtureRunAtProof.classify(
                runAt: "document_start",
                snapshot: nil
            )
        let domOnlySnapshot =
            ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
                frameID: "top",
                accessible: true,
                markerObserved: true,
                markerAttributeValue: "top",
                markerTokenValue:
                    ChromeMV3ContentScriptSmokeFixturePolicy.markerToken,
                executionReadyState: nil,
                pageWorldGlobalValue: nil,
                evaluationTarget: "mainFrame",
                reason: nil
            )
        let world =
            ChromeMV3ContentScriptLocalFixtureWorldProof.classify(
                declaredWorld: "MAIN",
                snapshot: domOnlySnapshot
            )

        XCTAssertFalse(missingRunAt.exactRunAtTimingObserved)
        XCTAssertEqual(missingRunAt.proofLevel, "unverified")
        XCTAssertTrue(world.pageVisibleMarkerObserved)
        XCTAssertFalse(world.exactWorldExecutionVerified)
        XCTAssertEqual(world.proofLevel, "pageVisibleDOMOnly")
    }

    @MainActor
    func testDisabledModuleBlocksLocalFixtureRunnerAndWritesNoReport()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 local fixture runner requires macOS 15.5.")
        }

        let root = try makeLocalContentScriptRoot(
            named: "local-fixture-disabled"
        )
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = LocalFixtureModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let report = await module
            .chromeMV3RuntimeContentScriptLocalFixtureRunnerReportIfEnabled(
                explicitInternalLocalFixtureRunnerAllowed: true,
                explicitLocalHTTPServerAllowed: true,
                explicitSyntheticWebViewCreationAllowed: true,
                explicitSyntheticNavigationAllowed: true,
                explicitTestDOMInspectionAllowed: true,
                candidate: candidate,
                writeReport: true
            )

        XCTAssertNil(report)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ChromeMV3ContentScriptLocalFixtureRunnerReportWriter
                        .reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testRunnerRecordsContextLoadUnavailableAndWritesReportWithoutServer()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 local fixture runner requires macOS 15.5.")
        }

        let root = try makeLocalContentScriptRoot(
            named: "local-fixture-runner-context-unavailable"
        )
        let candidate = makeCandidate(rootURL: root)
        let runtimeReport = runtimeLoadabilityReport(rootPath: root.path)
        let objectReport = objectAcceptanceReport(
            rootURL: root,
            accepted: true,
            runtimeReport: runtimeReport
        )

        let report = await ChromeMV3ContentScriptLocalFixtureRunner.run(
            candidate: candidate,
            extensionsModuleEnabled: true,
            explicitInternalLocalFixtureRunnerAllowed: true,
            explicitLocalHTTPServerAllowed: true,
            explicitSyntheticWebViewCreationAllowed: true,
            explicitSyntheticNavigationAllowed: true,
            explicitTestDOMInspectionAllowed: true,
            objectAcceptanceReport: objectReport,
            runtimeBridgeReadinessReport: nil,
            emptyControllerOwner: nil,
            detachedContextOwner: nil,
            controllerLoadOwner: nil
        )
        try ChromeMV3ContentScriptLocalFixtureRunnerReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        XCTAssertTrue(
            report.prerequisiteState.blockedByContextLoadUnavailable
        )
        XCTAssertEqual(
            report.nextRecommendedAction,
            .blockedByContextLoadUnavailable
        )
        XCTAssertFalse(report.localFixtureSetupResult.serverStarted)
        XCTAssertEqual(report.navigationCompletionState, "notStarted")
        XCTAssertEqual(report.testDOMInspection, .notAttempted)
        XCTAssertTrue(report.matrixCases.isEmpty == false)
        XCTAssertTrue(report.matrixCases.allSatisfy {
            $0.actualObservation == .blocked
        })
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.productRuntimeExposed)
        assertLocalFixtureRuntimeCountersStayUnavailable(report)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ChromeMV3ContentScriptLocalFixtureRunnerReportWriter
                        .reportFileName
                ).path
            )
        )
    }

    func testSourceGuardsForLocalFixtureRunnerBoundary() throws {
        let chromeMV3Source = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let testSource = try Self.sourceFiles(in: [
            "SumiTests",
        ]).filter { $0.relativePath.contains("ChromeMV3") }
        let runtimeJSBridgeScopedFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
            "SumiTests/ChromeMV3TabsScriptingJSMVPTests.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift",
            "SumiTests/ChromeMV3StorageLocalRuntimeTests.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerRealPackageCompatibility.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift",
            "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift",
            "SumiTests/ChromeMV3PasswordManagerRealPackageCompatibilityTests.swift",
        ]
        let joined = (chromeMV3Source + testSource)
            .filter { source in
                runtimeJSBridgeScopedFiles.contains {
                    source.relativePath.hasSuffix($0)
                } == false
            }
            .map(\.contents)
            .joined(separator: "\n")

        for forbidden in [
            "WK" + "UserScript(",
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
            "runtime" + "Loadable.*" + "tr" + "ue",
            "chrome" + "RuntimeAvailableNow.*" + "tr" + "ue",
            "js" + "BridgeAvailableNow.*" + "tr" + "ue",
            "product" + "RuntimeExposed.*" + "tr" + "ue",
            "product" + "NormalTabAttachmentCount.*[1-9]",
            "service" + "WorkerWakeCount.*[1-9]",
            "runtime" + "DispatchCount.*[1-9]",
            "native" + "MessagingPortCount.*[1-9]",
            "pro" + "cessLaunchCount.*[1-9]",
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

    private func assertLocalFixtureRuntimeCountersStayUnavailable(
        _ report: ChromeMV3ContentScriptLocalFixtureRunnerReport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(report.runtimeLoadable, file: file, line: line)
        XCTAssertFalse(
            report.chromeRuntimeAvailableNow,
            file: file,
            line: line
        )
        XCTAssertFalse(report.jsBridgeAvailableNow, file: file, line: line)
        XCTAssertFalse(report.productRuntimeExposed, file: file, line: line)
        XCTAssertEqual(
            report.sideEffectCounters.sumiWKUserScriptCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.sumiAddUserScriptCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.scriptMessageHandlerCount,
            0,
            file: file,
            line: line
        )
        XCTAssertFalse(
            report.sideEffectCounters.jsBridgeAvailableNow,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.serviceWorkerWakeCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.runtimeDispatchCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.runtimePortCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.nativeMessagingPortCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.processLaunchCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.productNormalTabAttachmentCount,
            0,
            file: file,
            line: line
        )
    }

    private func localFixtureGateInput(
        rootURL: URL,
        explicitInternalLocalFixtureRunnerAllowed: Bool = true,
        loadedContextAvailable: Bool = true,
        sameControllerAvailable: Bool = true
    ) throws -> ChromeMV3ContentScriptLocalFixtureGateInput {
        let contentPolicy =
            ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                acceptedWebExtensionObjectAvailable: true,
                detachedContextCreated: true,
                options:
                    ChromeMV3ContentScriptSmokeFixturePolicyOptions(
                        allowedTestOriginHosts: ["127.0.0.1", "localhost"],
                        allowBroadPatternsForExplicitTestFixture: false
                    )
            )
        let loadDecision = ChromeMV3ControllerLoadGateDecision(
            input: ChromeMV3ControllerLoadGateInput(
                candidateID: "local-fixture-candidate",
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier: "local-fixture-profile",
                explicitInternalControllerLoadProbeAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: nil,
                objectAcceptanceReport: nil,
                detachedContextOwnerDiagnostics: nil,
                emptyControllerDiagnostics: nil,
                liveNormalTabAttachmentSnapshot: nil,
                runtimeBridgeReadinessReport: nil,
                minimalInertFixturePolicy:
                    ChromeMV3MinimalInertFixturePolicy.evaluate(
                        generatedRewrittenRootPath:
                            rootURL.standardizedFileURL.path,
                        acceptedWebExtensionObjectAvailable: true,
                        detachedContextCreated: true
                    ),
                contentScriptSmokeFixturePolicy: contentPolicy,
                sdkCompatibility: .currentAppleSDK,
                requestedProductRuntimeExposure: false,
                requestedExtensionCodeExecution: false,
                requestedUserScriptRegistration: false,
                requestedNativeMessagingLaunch: false
            ),
            canLoadContextIntoControllerNow: true,
            loadAttemptAllowed: true,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false,
            runtimeLoadable: false,
            blockers: [],
            blockingReasons: [],
            warnings: [],
            diagnostics: [],
            sameControllerValidation:
                ChromeMV3ControllerLoadSameControllerValidation.make(
                    acceptedWebExtensionObjectAvailable: true,
                    detachedDiagnostics: nil,
                    emptyControllerDiagnostics: nil,
                    liveSnapshot: nil
                ),
            sideEffectGuardDiagnostics:
                ChromeMV3ControllerLoadSideEffectGuardDiagnostics.make(
                    emptyControllerDiagnostics: nil,
                    runtimeBridgeReadinessReport: nil,
                    loadAttempted: loadedContextAvailable
                )
        )
        let loadDiagnostics = ChromeMV3ControllerLoadOwnerDiagnostics.make(
            state:
                loadedContextAvailable
                    ? .loadedIntoController
                    : .notAttempted,
            gateDecision: loadDecision,
            controllerLoadAttempted: loadedContextAvailable,
            contextLoadedIntoController: loadedContextAvailable,
            controllerLoadCount: loadedContextAvailable ? 1 : 0
        )
        return ChromeMV3ContentScriptLocalFixtureGateInput(
            runnerID:
                ChromeMV3ContentScriptLocalFixtureRunnerID(
                    rawValue: "local-fixture-test-runner"
                ),
            fixtureID:
                ChromeMV3ContentScriptLocalFixtureID(
                    rawValue: "local-fixture-test"
                ),
            generatedRewrittenRootPath:
                rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: true,
            explicitInternalLocalFixtureRunnerAllowed:
                explicitInternalLocalFixtureRunnerAllowed,
            explicitLocalHTTPServerAllowed: true,
            explicitSyntheticWebViewCreationAllowed: true,
            explicitSyntheticNavigationAllowed: true,
            explicitTestDOMInspectionAllowed: true,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextAvailable: true,
            contentScriptFixturePolicy: contentPolicy,
            controllerLoadGateDecision: loadDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot: nil,
            runtimeBridgeReadinessReport: nil,
            sameControllerAvailable: sameControllerAvailable,
            requestedProductRuntimeExposure: false,
            requestedUserScriptRegistration: false,
            requestedRuntimeDispatch: false,
            requestedServiceWorkerWake: false,
            requestedNativeMessagingLaunch: false,
            requestedProductUI: false
        )
    }

    private func makeLocalContentScriptRoot(
        named name: String,
        allFrames: Bool = true,
        matchAboutBlank: Bool = true,
        matchOriginAsFallback: Bool = true,
        runAt: String = "document_idle",
        world: String? = "MAIN"
    ) throws -> URL {
        var manifest =
            ChromeMV3ContentScriptSmokeFixturePolicy.manifest(
                matches: ["http://127.0.0.1/*"],
                allFrames: allFrames,
                matchAboutBlank: matchAboutBlank,
                matchOriginAsFallback: matchOriginAsFallback,
                runAt: runAt,
                world: world
            )
        manifest["host_permissions"] = ["http://127.0.0.1/*"]
        return try makeSimpleRewrittenRoot(
            named: name,
            manifest: manifest,
            files: [
                "content-smoke-marker.js":
                    Self.localFixtureMarkerScript,
            ]
        )
    }

    private static var localFixtureMarkerScript: String {
        """
        (() => {
          const marker = "sumiChromeMV3ContentScriptSmokeMarker";
          const root = document.documentElement;
          if (!root) { return; }
          const frame = window.top === window ? "top" : "frame";
          const existing = root.getAttribute("data-sumi-mv3-content-script-smoke") || "";
          root.setAttribute("data-sumi-mv3-content-script-smoke", existing ? existing + "," + frame : frame);
          root.setAttribute("data-sumi-mv3-content-script-smoke-marker", marker);
          root.setAttribute("data-sumi-mv3-content-script-ready-state", document.readyState);
          window.__sumiMV3LocalFixtureWorldProbe = marker;
        })();

        """
    }

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (relativePath, contents) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func makeCandidate(
        rootURL: URL,
        id: String = "local-fixture-candidate"
    ) -> ChromeMV3RewrittenVariantCandidate {
        ChromeMV3RewrittenVariantCandidate(
            id: id,
            generatedVariantRootPath: nil,
            rewrittenVariantRootPath: rootURL.standardizedFileURL.path,
            runtimeLoadabilityReportPath: nil,
            rewrittenManifestSHA256: nil,
            runtimeLoadabilityReportSHA256: nil,
            manifestVersion: 3,
            rewrittenVariantExists: true
        )
    }

    private func objectAcceptanceReport(
        rootURL: URL,
        accepted: Bool,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        let candidate = makeCandidate(rootURL: rootURL)
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: objectProbeGateInput(
                rootURL: rootURL,
                candidate: candidate,
                runtimeReport: runtimeReport
            )
        )
        let diagnostics: ChromeMV3ExtensionObjectProbeDiagnostics = accepted
            ? .created(gateDecision: decision, parseErrors: [])
            : .blocked(gateDecision: decision)
        return ChromeMV3WebKitObjectAcceptanceReportGenerator.makeReport(
            candidate: candidate,
            gateDecision: decision,
            probeDiagnostics: diagnostics,
            runtimeLoadabilityReport: runtimeReport
        )
    }

    private func objectProbeGateInput(
        rootURL: URL,
        candidate: ChromeMV3RewrittenVariantCandidate,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport
    ) -> ChromeMV3ExtensionObjectProbeGateInput {
        ChromeMV3ExtensionObjectProbeGateInput(
            extensionsModuleEnabled: true,
            profileHostModuleState: .enabled,
            explicitInternalExtensionObjectProbeAllowed: true,
            resourceBaseURLPath: rootURL.standardizedFileURL.path,
            generatedBundleID: candidate.id,
            generatedBundleHash:
                runtimeReport.rewrittenManifestHash?.sha256,
            generatedRewrittenBundleExists: true,
            runtimeLoadabilityReportExists: true,
            runtimeLoadabilityReportID: runtimeReport.id,
            runtimeLoadabilityReportPath:
                candidate.runtimeLoadabilityReportPath,
            runtimeLoadabilityReportSHA256:
                candidate.runtimeLoadabilityReportSHA256,
            manifestVersion: 3,
            runtimeLoadable: false,
            staticRuntimeBlockers: runtimeReport.blockers,
            requestedContextCreation: false,
            requestedContextLoading: false,
            requestedControllerLoad: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            staleAttachedWebViewCount: 0
        )
    }

    private func runtimeLoadabilityReport(
        rootPath: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-local-fixture-runner-test",
            generatedVariantRootPath: rootPath,
            generatedVariantRootRelativeName: "generated-rewritten",
            sourceApplicationReportHash: nil,
            rewrittenManifestHash: ChromeMV3RuntimeLoadabilityFileHash(
                relativePath: "manifest.json",
                sha256: String(repeating: "1", count: 64),
                byteCount: 128
            ),
            runtimeTemplateFileHashes: [],
            extensionPageRewrittenFileHashes: [],
            extensionPageStaticChecks: [],
            verificationChecks: [],
            passedChecks: [.manifestShape],
            failedChecks: [],
            deferredChecks: [],
            warnings: [],
            missing: [],
            blockers: [],
            unsupportedAPIs: [],
            deferredAPIs: [],
            requiredFutureRuntimeComponents: [],
            passwordManagerReadiness:
                ChromeMV3PasswordManagerRuntimeReadinessReport(
                    contentScriptsPresent: true,
                    allFramesDetected: true,
                    matchAboutBlankDetected: true,
                    hostPermissionsPresent: false,
                    actionPopupPresent: false,
                    storagePermissionPresent: false,
                    nativeMessagingDetected: false,
                    nativeMessagingBlocked: true,
                    runtimeMessagingImplemented: false,
                    controlledInputPageWorldBehaviorVerified: false,
                    serviceWorkerLifecycleVerified: false,
                    blockers: [],
                    deferredChecks: []
                ),
            structurallyValid: true,
            runtimeLoadable: false,
            runtimeLoadableFalseReason:
                "Local fixture runner test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    @MainActor
    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: LocalFixtureModuleProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            managerFactory: { context, profile, configuration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: profile,
                    browserConfiguration: configuration
                )
            }
        )
    }

    private static func sourceFiles(
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
                includingPropertiesForKeys: nil
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                let relativePath = fileURL.path
                    .replacingOccurrences(
                        of: root.appendingPathComponent("").path,
                        with: ""
                    )
                results.append(
                    (
                        relativePath,
                        try String(contentsOf: fileURL, encoding: .utf8)
                    )
                )
            }
        }
        return results
    }
}

@MainActor
private final class LocalFixtureModuleProbe {
    var managerCount = 0
}
