import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ContentScriptSmokeHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testControlledContentScriptFixturePolicyPassesAndMinimalInertIsSeparate()
        throws
    {
        let contentRoot = try makeContentScriptRoot(
            named: "content-policy-pass"
        )
        let contentPolicy = ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: contentRoot.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
        let inertRoot = try makeSimpleRewrittenRoot(
            named: "content-policy-minimal-inert"
        )
        let inertPolicy = ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: inertRoot.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )

        XCTAssertTrue(contentPolicy.loadSafeForContentScriptSmokeFixture)
        XCTAssertEqual(
            contentPolicy.fixtureKind,
            .controlledInertContentScript
        )
        XCTAssertEqual(contentPolicy.manifestSummary.contentScriptCount, 1)
        XCTAssertEqual(
            contentPolicy.manifestSummary.contentScriptMetadata.first?
                .runAt,
            "document_idle"
        )
        XCTAssertEqual(
            contentPolicy.manifestSummary.matchPatterns,
            ["https://sumi.test/*"]
        )
        XCTAssertEqual(
            contentPolicy.scriptResources.first?.inertMarker,
            true
        )
        XCTAssertFalse(inertPolicy.loadSafeForContentScriptSmokeFixture)
        XCTAssertEqual(
            inertPolicy.fixtureKind,
            .minimalInertNonContentScript
        )
        XCTAssertTrue(inertPolicy.blockers.contains(.contentScriptsMissing))
    }

    func testFixturePolicyBlocksNativeBackgroundBroadAndRuntimeScriptShapes()
        throws
    {
        let nativeRoot = try makeContentScriptRoot(
            named: "content-policy-native",
            manifest: contentScriptManifest(permissions: ["nativeMessaging"])
        )
        let serviceWorkerRoot = try makeContentScriptRoot(
            named: "content-policy-worker",
            manifest: contentScriptManifest(
                extra: ["background": ["service_worker": "background.js"]]
            ),
            files: ["background.js": ""]
        )
        let broadRoot = try makeContentScriptRoot(
            named: "content-policy-broad",
            manifest: contentScriptManifest(matches: ["<all_urls>"])
        )
        let runtimeScriptRoot = try makeContentScriptRoot(
            named: "content-policy-runtime-script",
            script:
                ChromeMV3ContentScriptSmokeFixturePolicy.markerToken
                    + "\nchrome.runtime.sendMessage({});\n"
        )

        let nativePolicy = policy(nativeRoot)
        let serviceWorkerPolicy = policy(serviceWorkerRoot)
        let broadPolicy = policy(broadRoot)
        let broadAllowedPolicy =
            ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
                generatedRewrittenRootPath: broadRoot.path,
                acceptedWebExtensionObjectAvailable: true,
                detachedContextCreated: true,
                options:
                    ChromeMV3ContentScriptSmokeFixturePolicyOptions(
                        allowedTestOriginHosts:
                            ChromeMV3ContentScriptSmokeFixturePolicyOptions
                            .default
                            .allowedTestOriginHosts,
                        allowBroadPatternsForExplicitTestFixture: true
                    )
            )
        let runtimeScriptPolicy = policy(runtimeScriptRoot)

        XCTAssertTrue(
            nativePolicy.blockers.contains(.nativeMessagingPermissionPresent)
        )
        XCTAssertTrue(
            serviceWorkerPolicy.blockers
                .contains(.backgroundServiceWorkerPresent)
        )
        XCTAssertTrue(
            broadPolicy.blockers.contains(.contentScriptBroadMatchPattern)
        )
        XCTAssertFalse(
            broadAllowedPolicy.blockers
                .contains(.contentScriptBroadMatchPattern)
        )
        XCTAssertTrue(
            runtimeScriptPolicy.blockers
                .contains(.contentScriptRuntimeMessagingDetected)
        )
        XCTAssertFalse(runtimeScriptPolicy.loadSafeForContentScriptSmokeFixture)
    }

    func testFrameMatrixModelsTopAllFramesMatchAboutBlankAndUnsupportedCases()
        throws
    {
        let topOnlyRoot = try makeContentScriptRoot(
            named: "content-matrix-top"
        )
        let topOnly = policy(topOnlyRoot)
        let topOnlyMatrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: "top-only",
            manifestSummary: topOnly.manifestSummary
        )

        XCTAssertTrue(
            topOnlyMatrix.expectedEligibleFrames.map(\.frameID)
                .contains("top")
        )
        XCTAssertTrue(
            topOnlyMatrix.expectedBlockedFrames.map(\.frameID)
                .contains("same-origin")
        )

        let allFramesRoot = try makeContentScriptRoot(
            named: "content-matrix-all",
            manifest: contentScriptManifest(
                allFrames: true,
                matchAboutBlank: true,
                matchOriginAsFallback: true,
                runAt: "document_start",
                world: "MAIN"
            )
        )
        let allFrames = policy(allFramesRoot)
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: "all-frames",
            manifestSummary: allFrames.manifestSummary
        )
        let eligible = matrix.expectedEligibleFrames.map(\.frameID)
        let blocked =
            matrix.expectedBlockedFrames.map(\.frameID)

        XCTAssertTrue(eligible.contains("top"))
        XCTAssertTrue(eligible.contains("same-origin"))
        XCTAssertTrue(eligible.contains("about-blank"))
        XCTAssertTrue(eligible.contains("data"))
        XCTAssertTrue(eligible.contains("blob"))
        XCTAssertTrue(blocked.contains("cross-origin"))
        XCTAssertTrue(
            matrix.allDecisions.first { $0.frameID == "same-origin" }?
                .observationBlockers
                .blockedByCurrentSDKShape == true
        )
        XCTAssertTrue(
            matrix.allDecisions.first { $0.frameID == "data" }?
                .observationBlockers
                .blockedByUnsafeObservationMechanism == true
        )
        XCTAssertEqual(
            matrix.allDecisions.first { $0.frameID == "top" }?.runAt,
            "document_start"
        )
        XCTAssertEqual(
            matrix.allDecisions.first { $0.frameID == "top" }?.world,
            "MAIN"
        )
    }

    func testSyntheticHTMLFixtureGenerationHasNoNetworkProductTabOrWindow()
        throws
    {
        let root = try makeContentScriptRoot(
            named: "content-html-fixture",
            manifest: contentScriptManifest(
                allFrames: true,
                matchAboutBlank: true
            )
        )
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: "html-fixture",
            manifestSummary: policy(root).manifestSummary
        )
        let fixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: matrix
        )

        XCTAssertFalse(fixture.networkDependency)
        XCTAssertFalse(fixture.productTabRequired)
        XCTAssertFalse(fixture.userVisibleWindowRequired)
        XCTAssertTrue(fixture.topHTML.contains("top-frame-marker"))
        XCTAssertTrue(fixture.topHTML.contains("same-origin-frame"))
        XCTAssertTrue(fixture.topHTML.contains("cross-origin-frame"))
        XCTAssertTrue(fixture.topHTML.contains("about-blank-frame"))
        XCTAssertTrue(fixture.topHTML.contains("data-frame"))
        XCTAssertTrue(fixture.topHTML.contains("blob-frame"))
        XCTAssertNotNil(
            fixture.frames.first {
                $0.kind == .crossOriginIframe
                    && $0.includedInTopHTML == false
            }
        )
    }

    @MainActor
    func testDisabledModuleBlocksContentScriptSmokeAndWritesNoReport() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 content-script smoke requires macOS 15.5.")
        }

        let root = try makeContentScriptRoot(named: "content-disabled")
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ContentScriptModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let report = module.chromeMV3RuntimeContentScriptSmokeReportIfEnabled(
            explicitInternalContentScriptSmokeAllowed: true,
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
                    ChromeMV3ContentScriptSmokeReportWriter.reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testRunWithTestDOMInspectionAttemptsExpandedMatrixWhenWebKitAcceptsFixture()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 content-script smoke requires macOS 15.5.")
        }

        let root = try makeContentScriptRoot(
            named: "content-dom-inspection-run",
            manifest: contentScriptManifest(
                allFrames: true,
                matchAboutBlank: true,
                matchOriginAsFallback: true
            )
        )
        let candidate = makeCandidate(rootURL: root)
        let runtimeReport = runtimeLoadabilityReport(rootPath: root.path)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ContentScriptModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let probeDiagnostics = await module
            .runChromeMV3ExtensionObjectProbeIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: true,
                candidate: candidate,
                runtimeLoadabilityReport: runtimeReport
            )
        guard probeDiagnostics?.state == .created else {
            throw XCTSkip(
                "WKWebExtension object probe failed: \(probeDiagnostics?.error?.message ?? "unknown")"
            )
        }
        let objectReport = try XCTUnwrap(
            module.chromeMV3WebKitObjectAcceptanceReportIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: true,
                candidate: candidate,
                runtimeLoadabilityReport: runtimeReport,
                probeDiagnostics: probeDiagnostics
            )
        )
        guard objectReport.objectAcceptedByWebKit else {
            throw XCTSkip("WKWebExtension object was not accepted.")
        }
        let emptyOwner = try XCTUnwrap(
            module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true,
                candidateRewrittenVariants: [candidate]
            )
        )
        let readiness = try runtimeBridgeReadinessReport(
            rootURL: root,
            runtimeLoadabilityReport: runtimeReport,
            objectAcceptanceReport: objectReport,
            emptyControllerDiagnostics: emptyOwner.diagnostics()
        )
        let contextDiagnostics =
            module.createChromeMV3DetachedContextIfEnabled(
                explicitInternalContextCreationAllowed: true,
                candidate: candidate,
                objectAcceptanceReport: objectReport,
                runtimeBridgeReadinessReport: readiness
            )
        guard contextDiagnostics?.contextObjectCreated == true else {
            throw XCTSkip("Detached WKWebExtensionContext was not created.")
        }
        let loadDiagnostics =
            module.loadChromeMV3DetachedContextIntoControllerIfEnabled(
                explicitInternalControllerLoadProbeAllowed: true,
                candidate: candidate,
                objectAcceptanceReport: objectReport,
                runtimeBridgeReadinessReport: readiness
            )
        guard loadDiagnostics?.contextLoadedIntoController == .some(!false)
        else {
            throw XCTSkip(
                "WKWebExtensionContext did not load into the controller: \(loadDiagnostics?.webKitError?.message ?? "unknown")"
            )
        }

        let reportOptional = await module
            .chromeMV3RuntimeContentScriptSmokeReportWithTestDOMInspectionIfEnabled(
                explicitInternalContentScriptSmokeAllowed: true,
                explicitSyntheticWebViewCreationAllowed: true,
                explicitSyntheticNavigationAllowed: true,
                explicitTestDOMInspectionAllowed: true,
                candidate: candidate,
                objectAcceptanceReport: objectReport,
                runtimeBridgeReadinessReport: readiness,
                writeReport: true
        )
        let report = try XCTUnwrap(reportOptional)

        XCTAssertTrue(report.observationResult.testDOMInspection.attempted)
        XCTAssertTrue(report.syntheticWebViewResult.syntheticNavigationAttempted)
        XCTAssertEqual(
            report.expandedMatrixResults.map(\.frameDecision.frameID),
            report.frameMatrixResult.allDecisions.map(\.frameID)
        )
        XCTAssertTrue(
            [.observed, .notObserved, .unverified]
                .contains(report.observationResult.state)
        )
        XCTAssertEqual(
            report.frameObservationResults.first { $0.frameID == "data" }?
                .observedMarker,
            .blocked
        )
        XCTAssertEqual(
            report.frameObservationResults.first {
                $0.frameID == "same-origin"
            }?.observationBlockers.blockedByCurrentSDKShape,
            true
        )
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.productRuntimeExposed)
        assertContentScriptRuntimeCountersStayUnavailable(report)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ChromeMV3ContentScriptSmokeReportWriter.reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testContentScriptSmokeGateRequiresExplicitFlagAndSameController()
        throws
    {
        let root = try makeContentScriptRoot(named: "content-gate")
        let missingFlag = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: try contentScriptSmokeGateInput(
                rootURL: root,
                explicitInternalContentScriptSmokeAllowed: false
            )
        )
        let missingSameController = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: try contentScriptSmokeGateInput(
                rootURL: root,
                sameControllerAvailable: false
            )
        )

        XCTAssertFalse(missingFlag.canRunContentScriptSmokeNow)
        XCTAssertTrue(
            missingFlag.blockers
                .contains(.explicitContentScriptSmokeNotAllowed)
        )
        XCTAssertFalse(missingSameController.canRunContentScriptSmokeNow)
        XCTAssertTrue(
            missingSameController.blockers.contains(.sameControllerMissing)
        )
        for decision in [missingFlag, missingSameController] {
            XCTAssertFalse(decision.runtimeLoadable)
            XCTAssertFalse(decision.chromeRuntimeAvailableNow)
            XCTAssertFalse(decision.jsBridgeAvailableNow)
            XCTAssertFalse(decision.productRuntimeExposed)
        }
    }

    func testObservationStrategyClassifierBlocksForbiddenStrategies() {
        let scope =
            ChromeMV3ContentScriptObservationStrategyScope.contentScriptSmoke(
                explicitTestDOMInspectionAllowed: true,
                sameControllerSyntheticConfiguration: true,
                syntheticNavigationAllowed: true,
                productNormalTabAttachmentCount: 0
            )
        let classifications =
            ChromeMV3ContentScriptObservationStrategyClassifier
            .classifyAll(scope: scope)

        XCTAssertEqual(
            classifications.first {
                $0.strategy == .blockedRequiresSumiInjection
            }?.allowedInThisPrompt,
            false
        )
        XCTAssertEqual(
            classifications.first {
                $0.strategy == .blockedRequiresScriptMessageHandler
            }?.allowedInThisPrompt,
            false
        )
        XCTAssertEqual(
            classifications.first {
                $0.strategy == .blockedRequiresJSBridge
            }?.allowedInThisPrompt,
            false
        )
        XCTAssertEqual(
            classifications.first {
                $0.strategy == .unsupportedByCurrentSDK
            }?.allowedInThisPrompt,
            false
        )
        XCTAssertTrue(classifications.allSatisfy {
            $0.productExposure == false
        })
    }

    func testTestDOMInspectionRequiresExplicitDebugInternalSyntheticScope() {
        let missingFlag =
            ChromeMV3ContentScriptObservationStrategyClassifier.classify(
                .testDOMInspection,
                scope:
                    ChromeMV3ContentScriptObservationStrategyScope
                    .contentScriptSmoke(
                        explicitTestDOMInspectionAllowed: false,
                        sameControllerSyntheticConfiguration: true,
                        syntheticNavigationAllowed: true,
                        productNormalTabAttachmentCount: 0
                    )
            )
        let attachedProductConfigurations = 1
        var productScope =
            ChromeMV3ContentScriptObservationStrategyScope.contentScriptSmoke(
                explicitTestDOMInspectionAllowed: true,
                sameControllerSyntheticConfiguration: true,
                syntheticNavigationAllowed: true,
                productNormalTabAttachmentCount:
                    attachedProductConfigurations
            )
        productScope.internalSyntheticWebViewOnly = false
        let productPath =
            ChromeMV3ContentScriptObservationStrategyClassifier.classify(
                .testDOMInspection,
                scope: productScope
            )
        let allowed =
            ChromeMV3ContentScriptObservationStrategyClassifier.classify(
                .testDOMInspection,
                scope:
                    ChromeMV3ContentScriptObservationStrategyScope
                    .contentScriptSmoke(
                        explicitTestDOMInspectionAllowed: true,
                        sameControllerSyntheticConfiguration: true,
                        syntheticNavigationAllowed: true,
                        productNormalTabAttachmentCount: 0
                    )
            )

        XCTAssertFalse(missingFlag.allowedInThisPrompt)
        XCTAssertTrue(
            missingFlag.reason
                .contains("explicit test DOM inspection flag")
        )
        XCTAssertFalse(productPath.allowedInThisPrompt)
        XCTAssertTrue(allowed.allowedInThisPrompt)
        XCTAssertEqual(allowed.riskLevel, .low)
    }

    func testMarkerFixtureFactsRemainInertAndPageVisible() {
        let facts = ChromeMV3ContentScriptMarkerFixtureFacts.inertMarker

        XCTAssertTrue(facts.deterministic)
        XCTAssertFalse(facts.runtimeMessaging)
        XCTAssertFalse(facts.serviceWorkerWake)
        XCTAssertFalse(facts.externalResources)
        XCTAssertFalse(facts.nativeMessaging)
        XCTAssertFalse(facts.dynamicCodeExecution)
        XCTAssertTrue(facts.pageVisibleDOMMarkerExpected)
        XCTAssertEqual(
            facts.markerToken,
            ChromeMV3ContentScriptSmokeFixturePolicy.markerToken
        )
    }

    func testFrameObservationModelPreservesEligibilityAndBlockedStates()
        throws
    {
        let root = try makeContentScriptRoot(
            named: "content-observation-model",
            manifest: contentScriptManifest(
                allFrames: true,
                matchAboutBlank: true
            )
        )
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: "observation-model",
            manifestSummary: policy(root).manifestSummary
        )
        let records =
            ChromeMV3ContentScriptFrameObservationModel
            .blockedOrUnverifiedRecords(
                matrix: matrix,
                strategy: .testDOMInspection,
                eligibleState: .blocked,
                reason: "Observation flag missing."
            )

        XCTAssertEqual(
            Set(records.map(\.frameID)),
            Set(matrix.allDecisions.map(\.frameID))
        )
        XCTAssertEqual(
            records.first { $0.frameID == "top" }?.expectedEligibility,
            .eligible
        )
        XCTAssertEqual(
            records.first { $0.frameID == "top" }?.observedMarker,
            .blocked
        )
        XCTAssertEqual(
            records.first { $0.frameID == "about-blank" }?
                .expectedEligibility,
            .eligible
        )
        XCTAssertEqual(
            records.first { $0.frameID == "same-origin" }?
                .observedMarker,
            .blocked
        )
        XCTAssertTrue(
            records.first { $0.frameID == "same-origin" }?
                .observationBlockers
                .blockedByCurrentSDKShape == true
        )
    }

    @MainActor
    func testExpandedMatrixClassifiesFrameControlsRunAtWorldAndBlockedReasons()
        throws
    {
        let root = try makeContentScriptRoot(
            named: "content-expanded-matrix",
            manifest: contentScriptManifest(
                allFrames: true,
                matchAboutBlank: true,
                matchOriginAsFallback: true,
                runAt: "document_end",
                world: "MAIN"
            )
        )
        let decision = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: try contentScriptSmokeGateInput(rootURL: root)
        )
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: "expanded-matrix",
            manifestSummary: policy(root).manifestSummary
        )
        let fixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: matrix
        )
        let records =
            ChromeMV3ContentScriptFrameObservationModel
            .blockedOrUnverifiedRecords(
                matrix: matrix,
                strategy: .testDOMInspection,
                reason: "Synthetic DOM inspection not run in this unit test."
            )
        let observation =
            ChromeMV3ContentScriptSmokeReportGenerator.observationResult(
                state: .unverified,
                strategy: .testDOMInspection,
                frameResults: records,
                blockedReasons: [],
                unverifiedNotes: []
            )
        let report = ChromeMV3ContentScriptSmokeReportGenerator.makeReport(
            gateDecision: decision,
            frameMatrixResult: matrix,
            syntheticHTMLFixture: fixture,
            syntheticWebViewResult:
                ChromeMV3ContentScriptSmokeReportGenerator
                .syntheticWebViewResult(
                    syntheticConfigurationCreated: true,
                    syntheticConfigurationAttached: true,
                    syntheticConfigurationUsesSameController: true,
                    syntheticWebViewCreated: true,
                    syntheticWebViewUsesSameController: true,
                    syntheticNavigationAttempted: true,
                    syntheticHTMLLoaded: true,
                    userScriptCount: 0,
                    blockingReasons: [],
                    warnings: []
                ),
            observationResult: observation
        )

        XCTAssertEqual(
            report.expandedMatrixResults.map(\.frameDecision.frameID),
            matrix.allDecisions.map(\.frameID)
        )
        let top = try XCTUnwrap(
            report.expandedMatrixResults.first {
                $0.frameDecision.frameID == "top"
            }
        )
        XCTAssertEqual(top.fixtureID, decision.input.scenario.fixtureID)
        XCTAssertEqual(top.runAt, "document_end")
        XCTAssertEqual(top.world, "MAIN")
        XCTAssertTrue(top.allFrames)
        XCTAssertTrue(top.matchAboutBlank)
        XCTAssertTrue(top.matchOriginAsFallback)
        XCTAssertEqual(top.expectedEligibility, .eligible)
        XCTAssertEqual(top.resultClassification, .unverified)
        XCTAssertEqual(top.runAtClassification.exactRunAtTiming, "unverified")
        XCTAssertFalse(top.worldClassification.exactWorldExecutionVerified)
        XCTAssertTrue(top.worldClassification.pageVisibleDOMMarkerExpected)

        let data = try XCTUnwrap(
            report.expandedMatrixResults.first {
                $0.frameDecision.frameID == "data"
            }
        )
        XCTAssertEqual(data.expectedEligibility, .eligible)
        XCTAssertEqual(data.resultClassification, .blocked)
        XCTAssertTrue(
            data.observationBlockers
                .blockedByUnsafeObservationMechanism
        )
        XCTAssertTrue(
            data.observationBlockers.needsManualWebKitVerification
        )
    }

    func testRunAtAndWorldClassificationDoNotOverclaimTimingOrWorld() {
        for runAt in ["document_start", "document_end", "document_idle"] {
            let classification =
                ChromeMV3ContentScriptRunAtClassification.classify(
                    runAt: runAt,
                    observedMarkerAfterLoad: true
                )
            XCTAssertTrue(classification.observedMarkerAfterLoad)
            XCTAssertEqual(classification.exactRunAtTiming, "unverified")
            XCTAssertTrue(classification.reason.contains(runAt))
        }

        let isolated =
            ChromeMV3ContentScriptWorldBehaviorClassification.classify(
                declaredWorld: "ISOLATED"
            )
        let main =
            ChromeMV3ContentScriptWorldBehaviorClassification.classify(
                declaredWorld: "MAIN"
            )
        let omitted =
            ChromeMV3ContentScriptWorldBehaviorClassification.classify(
                declaredWorld: nil
            )
        let unsupported =
            ChromeMV3ContentScriptWorldBehaviorClassification.classify(
                declaredWorld: "SIDEWAYS"
            )

        XCTAssertEqual(isolated.effectiveWorld, "ISOLATED")
        XCTAssertEqual(main.effectiveWorld, "MAIN")
        XCTAssertEqual(omitted.effectiveWorld, "ISOLATED")
        XCTAssertTrue(isolated.testDOMInspectionCanSeeMarker)
        XCTAssertTrue(main.testDOMInspectionCanSeeMarker)
        XCTAssertFalse(isolated.exactWorldExecutionVerified)
        XCTAssertFalse(main.exactWorldExecutionVerified)
        XCTAssertFalse(unsupported.supportedByCurrentModel)
    }

    @MainActor
    func testMissingExplicitObservationFlagBlocksObservation() throws {
        let root = try makeContentScriptRoot(named: "content-observation-flag")
        let decision = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: try contentScriptSmokeGateInput(
                rootURL: root,
                explicitTestDOMInspectionAllowed: false
            )
        )
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: decision.input.scenario.scenarioID,
            manifestSummary:
                decision.input.contentScriptFixturePolicy.manifestSummary
        )
        let fixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: matrix
        )
        let webViewResult =
            ChromeMV3ContentScriptSmokeReportGenerator
            .syntheticWebViewResult(
                syntheticConfigurationCreated: true,
                syntheticConfigurationAttached: true,
                syntheticConfigurationUsesSameController: true,
                syntheticWebViewCreated: true,
                syntheticWebViewUsesSameController: true,
                syntheticNavigationAttempted: true,
                syntheticHTMLLoaded: true,
                userScriptCount: 0,
                blockingReasons: [],
                warnings: []
            )
        let scope =
            ChromeMV3ContentScriptObservationStrategyScope.contentScriptSmoke(
                explicitTestDOMInspectionAllowed: false,
                sameControllerSyntheticConfiguration: true,
                syntheticNavigationAllowed: true,
                productNormalTabAttachmentCount: 0
            )
        let classifications =
            ChromeMV3ContentScriptObservationStrategyClassifier.classifyAll(
                scope: scope
            )
        let reason = classifications.first {
            $0.strategy == .testDOMInspection
        }?.reason ?? "missing classification"
        let records =
            ChromeMV3ContentScriptFrameObservationModel
            .blockedOrUnverifiedRecords(
                matrix: matrix,
                strategy: .testDOMInspection,
                eligibleState: .blocked,
                reason: reason
            )
        let observation =
            ChromeMV3ContentScriptSmokeReportGenerator
            .observationResult(
                state: .blocked,
                strategy: .testDOMInspection,
                frameResults: records,
                blockedReasons: [reason],
                unverifiedNotes: []
            )
        let report = ChromeMV3ContentScriptSmokeReportGenerator.makeReport(
            gateDecision: decision,
            frameMatrixResult: matrix,
            syntheticHTMLFixture: fixture,
            syntheticWebViewResult: webViewResult,
            observationResult: observation,
            observationStrategyClassifications: classifications
        )

        XCTAssertTrue(decision.canRunContentScriptSmokeNow)
        XCTAssertEqual(report.observationResult.state, .blocked)
        XCTAssertEqual(report.summary.outcome, .blocked)
        XCTAssertEqual(
            report.nextRecommendedAction,
            .blockedByUnsafeObservationMechanism
        )
        XCTAssertEqual(
            report.frameObservationResults.first { $0.frameID == "top" }?
                .observedMarker,
            .blocked
        )
        assertContentScriptRuntimeCountersStayUnavailable(report)
    }

    @MainActor
    func testReportIsDeterministicCarriesCountersAndProfileDiagnostics()
        throws
    {
        let root = try makeContentScriptRoot(named: "content-report")
        let decision = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: try contentScriptSmokeGateInput(
                rootURL: root,
                explicitSyntheticWebViewCreationAllowed: false,
                explicitSyntheticNavigationAllowed: false
            )
        )
        let matrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: decision.input.scenario.scenarioID,
            manifestSummary:
                decision.input.contentScriptFixturePolicy.manifestSummary
        )
        let fixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: matrix
        )
        let webViewResult =
            ChromeMV3ContentScriptSmokeReportGenerator
            .syntheticWebViewResult(
                syntheticConfigurationCreated: false,
                syntheticConfigurationAttached: false,
                syntheticConfigurationUsesSameController: false,
                syntheticWebViewCreated: false,
                syntheticWebViewUsesSameController: false,
                syntheticNavigationAttempted: false,
                syntheticHTMLLoaded: false,
                userScriptCount: 0,
                blockingReasons: [],
                warnings: []
            )
        let observation =
            ChromeMV3ContentScriptSmokeReportGenerator
            .observationResult(
                state: .unverified,
                blockedReasons: [
                    "Observation is blocked without forbidden Sumi injection.",
                ],
                unverifiedNotes: [
                    "WebKit-owned marker execution remains unverified.",
                ]
            )
        let report = ChromeMV3ContentScriptSmokeReportGenerator.makeReport(
            gateDecision: decision,
            frameMatrixResult: matrix,
            syntheticHTMLFixture: fixture,
            syntheticWebViewResult: webViewResult,
            observationResult: observation
        )
        try ChromeMV3ContentScriptSmokeReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let firstData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContentScriptSmokeReportWriter.reportFileName
            )
        )
        try ChromeMV3ContentScriptSmokeReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContentScriptSmokeReportWriter.reportFileName
            )
        )
        let host = ChromeMV3ProfileHost(
            profileIdentifier: "profile-content-smoke",
            extensionsEnabled: true,
            profileDataStoreIdentity:
                .profileIdentifier("profile-content-smoke"),
            candidateRewrittenVariants: [makeCandidate(rootURL: root)]
        )
        let diagnostics = host.diagnostics(
            runtimeContentScriptSmokeReport: report
        )

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3ContentScriptSmokeReportWriter.reportFileName
        )
        XCTAssertEqual(
            diagnostics.runtimeContentScriptSmokeReport,
            report
        )
        XCTAssertEqual(report.observationResult.state, .unverified)
        XCTAssertEqual(report.markerFixtureFacts.deterministic, true)
        XCTAssertFalse(report.observationStrategyClassifications.isEmpty)
        XCTAssertEqual(
            report.frameObservationResults.first { $0.frameID == "top" }?
                .expectedEligibility,
            .eligible
        )
        XCTAssertEqual(
            report.nextRecommendedAction,
            .blockedByUnsafeObservationMechanism
        )
        assertContentScriptRuntimeCountersStayUnavailable(report)
    }

    @MainActor
    func testSourceGuardsForContentScriptSmokeBoundary() throws {
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
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift",
            "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift",
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

    private func assertContentScriptRuntimeCountersStayUnavailable(
        _ report: ChromeMV3ContentScriptSmokeReport,
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

    @MainActor
    private func contentScriptSmokeGateInput(
        rootURL: URL,
        explicitInternalContentScriptSmokeAllowed: Bool = true,
        explicitSyntheticWebViewCreationAllowed: Bool = true,
        explicitSyntheticNavigationAllowed: Bool = true,
        explicitTestDOMInspectionAllowed: Bool = false,
        loadedContextAvailable: Bool = true,
        sameControllerAvailable: Bool = true
    ) throws -> ChromeMV3ContentScriptSmokeGateInput {
        let candidate = makeCandidate(rootURL: rootURL)
        let profileIdentifier = UUID().uuidString
        let runtimeReport = runtimeLoadabilityReport(rootPath: rootURL.path)
        let objectReport = objectAcceptanceReport(
            rootURL: rootURL,
            accepted: true,
            runtimeReport: runtimeReport
        )
        let emptyDiagnostics = emptyControllerDiagnostics(
            profileIdentifier: profileIdentifier
        )
        let readiness = try runtimeBridgeReadinessReport(
            rootURL: rootURL,
            runtimeLoadabilityReport: runtimeReport,
            objectAcceptanceReport: objectReport,
            emptyControllerDiagnostics: emptyDiagnostics
        )
        let contextDecision = ChromeMV3ContextCreationGate.evaluate(
            input: ChromeMV3ContextCreationGateInput(
                candidateID: candidate.id,
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier: profileIdentifier,
                explicitInternalContextCreationAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: nil,
                objectAcceptanceReport: objectReport,
                emptyControllerDiagnostics: emptyDiagnostics,
                liveNormalTabAttachmentSnapshot: nil,
                runtimeBridgeReadinessReport: readiness,
                sdkCompatibility: .currentAppleSDK,
                requestedContextLoading: false,
                requestedControllerLoad: false,
                requestedExtensionCodeExecution: false,
                requestedUserScriptRegistration: false,
                requestedNativeMessagingLaunch: false
            )
        )
        let detachedDiagnostics =
            ChromeMV3DetachedContextOwnerDiagnostics.make(
                state: .createdDetached,
                gateDecision: contextDecision,
                contextObjectCreated: true
            )
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
        let contentPolicy =
            ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                acceptedWebExtensionObjectAvailable: true,
                detachedContextCreated: true
            )
        let loadDecision = ChromeMV3ControllerLoadGate.evaluate(
            input: ChromeMV3ControllerLoadGateInput(
                candidateID: candidate.id,
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier: profileIdentifier,
                explicitInternalControllerLoadProbeAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: nil,
                objectAcceptanceReport: objectReport,
                detachedContextOwnerDiagnostics: detachedDiagnostics,
                emptyControllerDiagnostics: emptyDiagnostics,
                liveNormalTabAttachmentSnapshot: nil,
                runtimeBridgeReadinessReport: readiness,
                minimalInertFixturePolicy: minimalPolicy,
                contentScriptSmokeFixturePolicy: contentPolicy,
                sdkCompatibility: .currentAppleSDK,
                requestedProductRuntimeExposure: false,
                requestedExtensionCodeExecution: false,
                requestedUserScriptRegistration: false,
                requestedNativeMessagingLaunch: false
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

        return ChromeMV3ContentScriptSmokeGateInput(
            scenario: ChromeMV3ContentScriptSmokeScenario(
                scenarioID: "content-script-smoke-test",
                fixtureID:
                    "content-script-smoke-fixture:\(candidate.id)",
                extensionID: candidate.id,
                profileID: profileIdentifier
            ),
            generatedRewrittenRootPath:
                rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: true,
            explicitInternalContentScriptSmokeAllowed:
                explicitInternalContentScriptSmokeAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            explicitSyntheticNavigationAllowed:
                explicitSyntheticNavigationAllowed,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextAvailable: true,
            loadedContextAvailable: loadedContextAvailable,
            sameControllerAvailable: sameControllerAvailable,
            contentScriptFixturePolicy: contentPolicy,
            controllerLoadGateDecision: loadDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot: nil,
            runtimeBridgeReadinessReport: readiness,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedProductUI: false
        )
    }

    private func policy(
        _ rootURL: URL
    ) -> ChromeMV3ContentScriptSmokeFixturePolicyResult {
        ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootURL.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
    }

    private func makeContentScriptRoot(
        named name: String,
        manifest: [String: Any]? = nil,
        script: String =
            ChromeMV3ContentScriptSmokeFixturePolicy.inertMarkerScriptSource,
        files: [String: String] = [:]
    ) throws -> URL {
        var allFiles = files
        allFiles["content-smoke-marker.js"] = script
        return try makeSimpleRewrittenRoot(
            named: name,
            manifest: manifest ?? contentScriptManifest(),
            files: allFiles
        )
    }

    private func contentScriptManifest(
        matches: [String] = ["https://sumi.test/*"],
        permissions: [String] = [],
        allFrames: Bool = false,
        matchAboutBlank: Bool = false,
        matchOriginAsFallback: Bool = false,
        runAt: String = "document_idle",
        world: String? = "ISOLATED",
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var manifest =
            ChromeMV3ContentScriptSmokeFixturePolicy.manifest(
                matches: matches,
                allFrames: allFrames,
                matchAboutBlank: matchAboutBlank,
                matchOriginAsFallback: matchOriginAsFallback,
                runAt: runAt,
                world: world
            )
        if permissions.isEmpty == false {
            manifest["permissions"] = permissions
        }
        for (key, value) in extra {
            manifest[key] = value
        }
        return manifest
    }

    private func emptyControllerDiagnostics(
        profileIdentifier: String
    ) -> ChromeMV3EmptyControllerDiagnostics {
        let identity = ChromeMV3ProfileDataStoreIdentity
            .profileIdentifier(profileIdentifier)
        let decision = ChromeMV3ControllerCreationGate.evaluate(
            input: ChromeMV3ControllerCreationGateInput(
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileHostControllerState: .absentNotCreated,
                explicitControllerCreationAllowed: true,
                requestedContextLoading: false,
                requestedNormalTabAttachment: false,
                profileIdentifier: profileIdentifier,
                profileDataStoreIdentity: identity,
                disabledRuntimeInvariantStatus: .satisfied
            )
        )
        return ChromeMV3EmptyControllerDiagnostics(
            profileIdentifier: profileIdentifier,
            profileDataStoreIdentity: identity,
            dataStoreIdentityPolicy:
                ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
                    profileIdentifier: profileIdentifier,
                    dataStoreIdentity: identity,
                    controllerCreated: true
                ),
            controllerState: .createdEmpty,
            controllerCreated: true,
            gateDecision: decision,
            teardownPolicy: nil,
            contextCount: 0,
            loadedExtensionCount: 0,
            attachedWebViewCount: 0,
            nativeMessagingPortCount: 0,
            pendingContextLoads: 0,
            pendingAttachments: 0,
            configurationWebViewHasControllerAttachment: false,
            configurationWebViewUserScriptCount: 0,
            registersUserScriptsNow: false,
            launchesNativeMessagingNow: false,
            startsBackgroundWorkNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            runtimeLoadable: false,
            blockingReasons: [],
            liveNormalTabAttachmentSnapshot: .empty
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
            : .failed(
                gateDecision: decision,
                error: ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                    nsError: NSError(
                        domain: "SumiTests.ContentScriptSmoke",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Synthetic object rejection.",
                        ]
                    )
                )
            )
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

    private func runtimeBridgeReadinessReport(
        rootURL: URL,
        runtimeLoadabilityReport:
            ChromeMV3RuntimeLoadabilityReport,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport,
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics
    ) throws -> ChromeMV3RuntimeBridgeReadinessReport {
        let contextReport = ChromeMV3ContextReadinessReportGenerator
            .makeReport(
                candidate: makeCandidate(rootURL: rootURL),
                objectAcceptanceReport: objectAcceptanceReport,
                emptyControllerDiagnostics: emptyControllerDiagnostics,
                runtimeLoadabilityReport: runtimeLoadabilityReport
            )
        let prerequisites =
            ChromeMV3RuntimeBridgePrerequisitesReportGenerator.makeReport(
                contextReadinessReport: contextReport,
                contextReadinessReportPath:
                    rootURL.appendingPathComponent(
                        ChromeMV3ContextReadinessReportWriter.reportFileName
                    ).path
            )
        return ChromeMV3RuntimeBridgeReadinessReportGenerator.makeReport(
            prerequisitesReport: prerequisites,
            prerequisitesReportPath:
                rootURL.appendingPathComponent(
                    ChromeMV3RuntimeBridgePrerequisitesReportWriter
                        .reportFileName
                ).path,
            contextReadinessReport: contextReport
        )
    }

    private func runtimeLoadabilityReport(
        rootPath: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-content-script-smoke-test",
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
                    allFramesDetected: false,
                    matchAboutBlankDetected: false,
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
                "Content-script smoke test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Content Script Smoke",
            "version": "1.0.0",
        ],
        files: [String: String] = [:]
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
        id: String = "runtime-content-script-smoke-candidate"
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
        probe: ContentScriptModuleProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: {
                probe.profileProviderCount += 1
                return probe.profile
            },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                probe.ownerFactoryCount += 1
                return ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            }
        )
    }

    private static func sourceFiles(
        in relativeDirectories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = repoRoot
        return try relativeDirectories.flatMap { relativeDirectory in
            let directoryURL = root.appendingPathComponent(relativeDirectory)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else {
                return [(relativePath: String, contents: String)]()
            }

            var files: [(relativePath: String, contents: String)] = []
            for case let url as URL in enumerator {
                guard url.pathExtension == "swift" else { continue }
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey]
                )
                guard values.isRegularFile == true else { continue }
                let relativePath = String(
                    url.path.dropFirst(root.path.count + 1)
                )
                files.append(
                    (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                )
            }
            return files
        }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class ContentScriptModuleProbe {
    let profile = Profile(name: "Chrome MV3 Content Script Smoke Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
