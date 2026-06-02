import Foundation
import XCTest

@testable import Sumi

#if DEBUG
final class ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapterTests:
    XCTestCase
{
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testPolicyIsDefaultOffSyntheticReviewedFileIsolatedTopFrameOnly() {
        let policy =
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionPolicy
            .bitwardenDetectFill

        XCTAssertTrue(
            policy.webKitProgrammaticInjectionAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            policy.webKitProgrammaticInjectionAvailableByDefault
        )
        XCTAssertTrue(policy.syntheticHarnessOnly)
        XCTAssertTrue(policy.reviewedGeneratedBundleFileOnly)
        XCTAssertTrue(policy.isolatedWorldOnly)
        XCTAssertTrue(policy.topFrameOnly)
        XCTAssertFalse(policy.mainWorldAllowed)
        XCTAssertFalse(policy.multiFrameAllowed)
        XCTAssertFalse(policy.fileSchemeAllowed)
        XCTAssertFalse(policy.productNormalTabAllowed)
        XCTAssertTrue(policy.teardownRequired)
    }

    @MainActor
    func testDisabledModuleAndDefaultGateBlockWebKitObjectCreation()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        var disabled = fixture.adapterRequest()
        disabled.moduleState = .disabled
        let disabledResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(disabled)

        XCTAssertFalse(disabledResult.allowed)
        XCTAssertTrue(disabledResult.blockers.contains(.moduleDisabled))
        XCTAssertFalse(disabledResult.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(disabledResult.teardown.completed)

        var gateClosed = fixture.adapterRequest()
        gateClosed.localExperimentalGateAllowed = false
        let gateClosedResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(gateClosed)

        XCTAssertFalse(gateClosedResult.allowed)
        XCTAssertTrue(
            gateClosedResult.blockers.contains(.localExperimentalGateClosed)
        )
        XCTAssertFalse(gateClosedResult.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(gateClosedResult.teardown.completed)
    }

    @MainActor
    func testReviewedGeneratedScriptExecutesInIsolatedTopFrameAndTearsDown()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(try makeFixture().adapterRequest())

        XCTAssertTrue(result.allowed, "\(result.blockers): \(result.diagnostics)")
        XCTAssertEqual(
            result.injectedReviewedFile,
            "content/bootstrap-autofill.js"
        )
        XCTAssertTrue(result.isolatedWorldUsed)
        XCTAssertTrue(result.topFrameOnly)
        XCTAssertTrue(result.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(result.nonPersistentWebsiteDataStoreUsed)
        XCTAssertEqual(result.userScriptAttachmentCount, 0)
        XCTAssertEqual(result.scriptMessageHandlerAttachmentCount, 1)
        XCTAssertTrue(result.navigationCompleted)
        XCTAssertTrue(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.fixedHarnessShimInstalled)
        XCTAssertTrue(result.fixedDetectFillDispatchCompleted)
        XCTAssertTrue(result.dummyValuesWrittenByActualWebKitExecutedScript)
        XCTAssertEqual(
            result.domObservationBefore.url,
            "https://sumi.local.test/login"
        )
        XCTAssertEqual(
            result.domObservationBefore.origin,
            "https://sumi.local.test"
        )
        XCTAssertTrue(result.domObservationBefore.initialValuesEmpty)
        XCTAssertEqual(
            result.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            result.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(result.domObservationAfter.finalValuesMatchDummyFill)
        XCTAssertTrue(result.teardown.completed)
        XCTAssertTrue(result.teardown.navigationDelegateDetached)
        XCTAssertEqual(result.teardown.userScriptCountAfterTeardown, 0)
        XCTAssertEqual(
            result.teardown.scriptMessageHandlerCountAfterTeardown,
            0
        )
        XCTAssertTrue(result.teardown.webViewReferenceReleased)
        XCTAssertTrue(result.teardown.configurationReferenceReleased)
    }

    @MainActor
    func testManualNormalTabSmokeExecutesReviewedFileOnSyntheticHTTPSOriginAndTearsDown()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .runManualNormalTabSmoke(try makeFixture().manualSmokeRequest())

        XCTAssertTrue(result.allowed, "\(result.blockers): \(result.diagnostics)")
        XCTAssertTrue(result.manualNormalTabSmokeAvailableInLocalExperimentalGate)
        XCTAssertFalse(result.manualNormalTabSmokeAvailableByDefault)
        XCTAssertFalse(result.productDefaultRuntimeAvailable)
        XCTAssertTrue(result.reviewedFileOnly)
        XCTAssertTrue(result.syntheticHTTPSOriginOnly)
        XCTAssertTrue(result.isolatedWorldOnly)
        XCTAssertTrue(result.topFrameOnly)
        XCTAssertFalse(result.auxiliarySurfaceAllowed)
        XCTAssertTrue(result.teardownRequired)
        XCTAssertTrue(result.normalTabConfigurationMarked)
        XCTAssertTrue(result.normalBrowsingSurfaceOnly)
        XCTAssertFalse(result.injectionPlan.managerReadoutExecutes)
        XCTAssertFalse(result.injectionPlan.productSupportClaimed)
        XCTAssertEqual(
            result.injectionPlan.reviewedScriptPath,
            "content/bootstrap-autofill.js"
        )
        XCTAssertEqual(result.injectionPlan.syntheticOrigin, "https://sumi.local.test")
        XCTAssertEqual(result.injectionPlan.targetFrame, "topFrame")
        XCTAssertEqual(result.injectionPlan.contentWorld, "ISOLATED")
        XCTAssertTrue(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.fixedHarnessShimInstalled)
        XCTAssertTrue(result.fixedDetectFillDispatchCompleted)
        XCTAssertEqual(result.fieldsTouched, [
            "sumi-login-email",
            "sumi-login-password",
        ])
        XCTAssertEqual(
            result.domObservationBefore.url,
            "https://sumi.local.test/login"
        )
        XCTAssertTrue(result.domObservationBefore.initialValuesEmpty)
        XCTAssertEqual(
            result.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            result.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(result.domObservationAfter.finalValuesMatchDummyFill)
        XCTAssertTrue(result.teardown.completed)
        XCTAssertEqual(result.teardown.retainedObjectCountAfterTeardown, 0)
        XCTAssertEqual(
            Set(result.teardown.verifiedTriggers),
            Set(ChromeMV3ProductNormalTabReadinessTeardownTrigger.allCases)
        )
        XCTAssertTrue(result.teardown.userScriptsCreated.isEmpty)
        XCTAssertTrue(result.teardown.handlersCreated.contains(
            "sumiBitwardenSyntheticCompletion"
        ))
        XCTAssertTrue(result.thrownErrors.isEmpty)
        XCTAssertEqual(result.webKitExecutionResult, "pass")
    }

    @MainActor
    func testManualNormalTabSmokeExecutesSyntheticReviewedMarkerFixture()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .runManualNormalTabSmoke(
                try makeSyntheticFixture().manualSmokeRequest()
            )

        XCTAssertTrue(result.allowed, "\(result.blockers): \(result.diagnostics)")
        XCTAssertEqual(
            result.injectionPlan.reviewedScriptPath,
            "content/sumi-reviewed-resource-marker.js"
        )
        XCTAssertTrue(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.fixedHarnessShimInstalled)
        XCTAssertTrue(result.fixedDetectFillDispatchCompleted)
        XCTAssertEqual(result.fieldsTouched, [
            "sumi-login-email",
            "sumi-login-password",
        ])
        XCTAssertEqual(
            result.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            result.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(result.domObservationAfter.finalValuesMatchDummyFill)
        XCTAssertTrue(result.teardown.completed)
        XCTAssertEqual(result.teardown.retainedObjectCountAfterTeardown, 0)
        XCTAssertTrue(
            result.teardown.endpointsCreated.contains(
                "synthetic reviewed-resource marker object"
            )
        )
        XCTAssertFalse(result.teardown.endpointsCreated.contains {
            $0.contains("Bitwarden")
        })
        XCTAssertTrue(result.thrownErrors.isEmpty)
        XCTAssertEqual(result.webKitExecutionResult, "pass")
    }

    @MainActor
    func testProductNormalTabExecutionExperimentUsesReviewedHashAndReportsCost()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let manualRequest = try makeFixture().manualSmokeRequest()
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .runProductNormalTabExecutionExperiment(
                ChromeMV3LocalExperimentalProductNormalTabExecutionExperimentRequest(
                    normalTabExecutionRequest: manualRequest,
                    localProductNormalTabExperimentGateAllowed: true,
                    requiredReviewedScriptSHA256:
                        try XCTUnwrap(
                            manualRequest.injectionPlan.generatedResourceHash
                        )
                )
            )

        XCTAssertTrue(result.allowed, "\(result.blockers): \(result.diagnostics)")
        XCTAssertTrue(
            result.productNormalTabExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(result.productNormalTabExperimentAvailableByDefault)
        XCTAssertFalse(result.productDefaultRuntimeAvailable)
        XCTAssertTrue(result.reviewedFileOnly)
        XCTAssertTrue(result.syntheticHTTPSOriginOnly)
        XCTAssertTrue(result.isolatedWorldOnly)
        XCTAssertTrue(result.topFrameOnly)
        XCTAssertFalse(result.auxiliarySurfaceAllowed)
        XCTAssertTrue(result.teardownRequired)
        XCTAssertEqual(result.url, "https://sumi.local.test/login")
        XCTAssertEqual(result.origin, "https://sumi.local.test")
        XCTAssertEqual(result.surfaceClassification, .normalTab)
        XCTAssertTrue(result.normalBrowsingSurfaceOnly)
        XCTAssertTrue(result.auxiliarySurfacesExcluded)
        XCTAssertTrue(result.reviewedScriptHashMatched)
        XCTAssertTrue(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.usernameFieldExistsBefore)
        XCTAssertTrue(result.passwordFieldExistsBefore)
        XCTAssertTrue(result.submitButtonExistsBefore)
        XCTAssertTrue(result.initialValuesEmpty)
        XCTAssertEqual(result.usernameValueAfter, "sumi-test-user@example.test")
        XCTAssertEqual(
            result.passwordValueAfter,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(result.dummyMarkersOnly)
        XCTAssertTrue(result.finalValuesMatchDummyFill)
        XCTAssertEqual(result.fieldsTouched, [
            "sumi-login-email",
            "sumi-login-password",
        ])
        XCTAssertTrue(result.teardown.completed)
        XCTAssertEqual(result.runtimeCost.retainedObjectCountAfterTeardown, 0)
        XCTAssertFalse(result.runtimeCost.backgroundWorkScheduled)
        XCTAssertFalse(result.runtimeCost.permanentRuntimeRetained)
        XCTAssertFalse(result.runtimeCost.serviceWorkerWakeAttempted)
        XCTAssertFalse(result.runtimeCost.nativeHostLaunchAttempted)
        XCTAssertFalse(result.runtimeCost.networkAuthAttempted)
        XCTAssertFalse(result.runtimeCost.normalTabInjectionOutsideExperiment)
        XCTAssertFalse(result.managerReadoutExecutedExperiment)
        XCTAssertFalse(result.productSupportClaimed)
    }

    @MainActor
    func testProductNormalTabExecutionExperimentBlocksHashMismatchBeforeObjects()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let manualRequest = try makeFixture().manualSmokeRequest()
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .runProductNormalTabExecutionExperiment(
                ChromeMV3LocalExperimentalProductNormalTabExecutionExperimentRequest(
                    normalTabExecutionRequest: manualRequest,
                    localProductNormalTabExperimentGateAllowed: true,
                    requiredReviewedScriptSHA256: String(repeating: "0", count: 64)
                )
            )

        XCTAssertFalse(result.allowed)
        XCTAssertTrue(result.attempted)
        XCTAssertTrue(result.blockers.contains(.blockedByMissingReviewedResource))
        XCTAssertFalse(result.reviewedScriptHashMatched)
        XCTAssertFalse(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.runtimeCost.runtimeObjectsCreatedDuringExperiment.isEmpty)
        XCTAssertTrue(result.teardown.completed)
        XCTAssertEqual(result.runtimeCost.retainedObjectCountAfterTeardown, 0)
    }

    @MainActor
    func testFixtureSuccessDoesNotImplyCurrentRealPackageReviewedHash()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let manualRequest = try makeFixture().manualSmokeRequest()
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .runProductNormalTabExecutionExperiment(
                ChromeMV3LocalExperimentalProductNormalTabExecutionExperimentRequest(
                    normalTabExecutionRequest: manualRequest,
                    localProductNormalTabExperimentGateAllowed: true,
                    requiredReviewedScriptSHA256:
                        ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                        .reviewedBitwardenBootstrapAutofillSHA256
                )
            )

        XCTAssertFalse(result.allowed)
        XCTAssertTrue(result.attempted)
        XCTAssertFalse(result.reviewedScriptHashMatched)
        XCTAssertFalse(result.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(result.blockers.contains(.blockedByMissingReviewedResource))
        XCTAssertTrue(result.runtimeCost.runtimeObjectsCreatedDuringExperiment.isEmpty)
        XCTAssertNotEqual(
            manualRequest.injectionPlan.generatedResourceHash,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
    }

    func testReviewedResourceAuditRecordsSourceGeneratedEqualityAndRegistry()
        throws
    {
        let attempt =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            .attempt(try makeFixture().modeledRequest())
        let audit = try XCTUnwrap(attempt.shapeAudit.reviewedResourceAudit)

        XCTAssertTrue(attempt.allowed)
        XCTAssertEqual(audit.resourcePath, "content/bootstrap-autofill.js")
        XCTAssertTrue(audit.sourceAndGeneratedByteEqual)
        XCTAssertEqual(audit.sourcePackageSHA256, audit.generatedResourceSHA256)
        XCTAssertEqual(
            audit.expectedReviewedSHA256,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
        XCTAssertEqual(
            audit.previousReviewedSHA256,
            "89b0c2ce4d57431ddbfc8a28992ddf2cd36f2d2bbe64657c89bc164c76fe2b58"
        )
        XCTAssertEqual(audit.reviewReason, "reviewedLocalPackageHashUpdated")
        XCTAssertTrue(audit.generatedBundleContained)
        XCTAssertTrue(audit.reviewedResourcePathExact)
        XCTAssertTrue(audit.packageOwned)
        XCTAssertTrue(audit.noRemoteScript)
        XCTAssertTrue(audit.noRuntimeGeneratedJS)
        XCTAssertTrue(audit.noNetworkAuthNativeHostRequirement)
        XCTAssertTrue(audit.compatibleWithIsolatedTopFrameSyntheticHTTPS)
        XCTAssertTrue(audit.shapeEquivalentToReviewedRecord)
        XCTAssertTrue(audit.shapeBlockers.isEmpty)
    }

    @MainActor
    func testReviewedResourceAuditBlocksGeneratedCopyMismatchBeforeObjects()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        try write(
            "changed generated copy",
            to:
                fixture.generated.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        let request = fixture.adapterRequest()
        let audit = try XCTUnwrap(
            request.modeledInjectionAttempt.shapeAudit.reviewedResourceAudit
        )
        let result = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(request)

        XCTAssertFalse(request.modeledInjectionAttempt.allowed)
        XCTAssertFalse(audit.sourceAndGeneratedByteEqual)
        XCTAssertTrue(audit.shapeBlockers.contains("sourceGeneratedCopyMismatch"))
        XCTAssertFalse(audit.shapeEquivalentToReviewedRecord)
        XCTAssertFalse(result.allowed)
        XCTAssertFalse(result.hiddenSyntheticWebViewCreated)
        XCTAssertTrue(
            result.blockers.contains(.reviewedScriptResolutionBlocked)
        )
        XCTAssertFalse(result.reviewedScriptExecutedByWebKit)
    }

    @MainActor
    func testManualNormalTabSmokeBlocksUnsafeGatesBeforeWebKitObjects()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        let cases: [
            (
                ChromeMV3LocalExperimentalNormalTabManualSmokeRequest,
                ChromeMV3ProductNormalTabReadinessBlocker
            )
        ] = [
            (
                fixture.manualSmokeRequest(
                    localExperimentalProductGateAllowed: false
                ),
                .blockedByLocalExperimentalGate
            ),
            (
                fixture.manualSmokeRequest(
                    urlString: "https://example.test/login",
                    hostPermissions: ["https://example.test/*"]
                ),
                .blockedByNonSyntheticOrigin
            ),
            (
                fixture.manualSmokeRequest(
                    urlString: "file:///tmp/login.html",
                    hostPermissions: []
                ),
                .blockedByScheme
            ),
            (
                fixture.manualSmokeRequest(
                    tabSurface: .faviconDownload
                ),
                .blockedByAuxiliarySurface
            ),
            (
                fixture.manualSmokeRequest(hostPermissions: []),
                .blockedByPermission
            ),
            (
                fixture.manualSmokeRequest(contentWorld: .main),
                .blockedByWorld
            ),
            (
                fixture.manualSmokeRequest(frameID: 1, isTopFrame: false),
                .blockedByFrame
            ),
            (
                fixture.manualSmokeRequest(reviewedResourcePresent: false),
                .blockedByMissingReviewedResource
            ),
            (
                fixture.manualSmokeRequest(productDefaultRuntimeAvailable: true),
                .blockedByRuntimeGate
            ),
            (
                fixture.manualSmokeRequest(matchAboutBlank: true),
                .blockedByNonSyntheticOrigin
            ),
            (
                fixture.manualSmokeRequest(matchOriginAsFallback: true),
                .blockedByNonSyntheticOrigin
            ),
        ]

        for (request, blocker) in cases {
            let result = await
                ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
                .runManualNormalTabSmoke(request)
            XCTAssertFalse(result.allowed, "\(blocker)")
            XCTAssertTrue(
                result.blockers.contains(blocker),
                "\(blocker): \(result.blockers)"
            )
            XCTAssertFalse(result.normalTabConfigurationMarked)
            XCTAssertFalse(result.reviewedScriptExecutedByWebKit)
            XCTAssertEqual(
                result.webKitExecutionResult,
                "blockedBeforeObjectCreation"
            )
            XCTAssertTrue(result.teardown.completed)
            XCTAssertEqual(result.teardown.retainedObjectCountAfterTeardown, 0)
        }
    }

    @MainActor
    func testMainWorldMultiFrameAndNonReviewedGeneratedScriptRemainBlocked()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try makeFixture()
        var mainWorld = fixture.adapterRequest()
        mainWorld.world = "MAIN"
        let mainWorldResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(mainWorld)
        XCTAssertTrue(mainWorldResult.blockers.contains(.isolatedWorldRequired))
        XCTAssertFalse(mainWorldResult.hiddenSyntheticWebViewCreated)

        var multiFrame = fixture.adapterRequest()
        multiFrame.frameIDs = [0, 1]
        multiFrame.allFrames = true
        let multiFrameResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(multiFrame)
        XCTAssertTrue(multiFrameResult.blockers.contains(.multiFrameBlocked))
        XCTAssertFalse(multiFrameResult.hiddenSyntheticWebViewCreated)

        var nonReviewedRequest = fixture.modeledRequest()
        nonReviewedRequest.files = ["content/not-reviewed.js"]
        let nonReviewedAttempt =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession()
            .attempt(nonReviewedRequest)
        var nonReviewed = fixture.adapterRequest()
        nonReviewed.modeledInjectionAttempt = nonReviewedAttempt
        let nonReviewedResult = await
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
            .run(nonReviewed)
        XCTAssertTrue(
            nonReviewedResult.blockers
                .contains(.reviewedGeneratedBundleFileRequired)
        )
        XCTAssertFalse(nonReviewedResult.hiddenSyntheticWebViewCreated)
    }

    @MainActor
    func testStableIgnoredAsyncRealPackageRunnerWritesReviewedLocalBitwardenArtifact()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let target = try XCTUnwrap(
            ChromeMV3PasswordManagerRealPackageTargetCatalog
                .explicitLocalTargets()
                .first { $0.targetClass == .bitwarden }
        )
        guard FileManager.default.fileExists(
            atPath: target.explicitAllowedLocalRoot
        ) else {
            throw XCTSkip("Local reviewed Bitwarden package is unavailable.")
        }
        let reportRoot =
            ChromeMV3PasswordManagerRealPackageAsyncExperimentArtifactWriter
            .diagnosticsRootURL(projectRootURL: try temporaryDirectory())

        XCTAssertNil(
            ChromeMV3PasswordManagerRealPackageAsyncExperimentArtifactWriter
                .latestArtifact(rootURL: reportRoot)
        )

        let report = await
            ChromeMV3PasswordManagerRealPackageTrialRunner
            .runWithSyntheticWebKitProgrammaticInjectionAdapter(
                rootURL: reportRoot,
                serviceWorkerTrialGateSource: .explicitTestTrial,
                writeReport: true,
                now: { Date(timeIntervalSince1970: 22) }
            )
        let artifactURL =
            ChromeMV3PasswordManagerRealPackageAsyncExperimentArtifactWriter
            .reportURL(rootURL: reportRoot)
        let artifact = try XCTUnwrap(
            ChromeMV3PasswordManagerRealPackageAsyncExperimentArtifactWriter
                .latestArtifact(rootURL: reportRoot)
        )
        let artifactString =
            String(data: try Data(contentsOf: artifactURL), encoding: .utf8)
                ?? ""
        let row = try XCTUnwrap(
            report.rows.first { $0.targetClass == .bitwarden }
        )
        let detectFill = row.bitwardenE2ESmoke.detectFillSmoke
        let adapter = detectFill.webKitProgrammaticInjectionResult

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(row.packageSource, .realLocalUnpacked)
        XCTAssertTrue(adapter.allowed, "\(adapter.blockers): \(adapter.diagnostics)")
        XCTAssertTrue(adapter.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(adapter.dummyValuesWrittenByActualWebKitExecutedScript)
        XCTAssertTrue(adapter.teardown.completed)
        XCTAssertTrue(detectFill.manualNormalTabSmokeResult.allowed)
        XCTAssertTrue(
            detectFill.manualNormalTabSmokeResult
                .reviewedScriptExecutedByWebKit
        )
        XCTAssertTrue(
            detectFill.manualNormalTabSmokeResult.teardown.completed
        )
        XCTAssertTrue(
            detectFill.manualNormalTabSmokeResult
                .normalTabConfigurationMarked
        )
        let productExperiment =
            detectFill.productNormalTabExecutionExperimentResult
        XCTAssertEqual(
            productExperiment.requiredReviewedScriptSHA256,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
        XCTAssertEqual(
            productExperiment.reviewedScriptSHA256,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
        XCTAssertTrue(productExperiment.reviewedScriptHashMatched)
        XCTAssertTrue(
            productExperiment.allowed,
            productExperiment.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(productExperiment.reviewedScriptExecutedByWebKit)
        XCTAssertTrue(productExperiment.finalValuesMatchDummyFill)
        XCTAssertEqual(
            productExperiment.runtimeCost.retainedObjectCountAfterTeardown,
            0
        )
        let audit = try XCTUnwrap(productExperiment.reviewedResourceAudit)
        XCTAssertEqual(audit.reviewReason, "reviewedLocalPackageHashUpdated")
        XCTAssertEqual(
            audit.sourcePackageSHA256,
            "7d3a88b4b1b8ae882a20ba4decd2df6fc9859c72fe1e7d3a5a60eabb6e7d5d8e"
        )
        XCTAssertEqual(audit.sourcePackageSHA256, audit.generatedResourceSHA256)
        XCTAssertEqual(
            audit.expectedReviewedSHA256,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
        XCTAssertEqual(audit.packageVersion, "2026.4.1")
        XCTAssertTrue(audit.sourceAndGeneratedByteEqual)
        XCTAssertTrue(audit.generatedBundleContained)
        XCTAssertTrue(audit.shapeEquivalentToReviewedRecord)
        XCTAssertTrue(audit.shapeBlockers.isEmpty)
        XCTAssertFalse(productExperiment.managerReadoutExecutedExperiment)
        XCTAssertEqual(artifact.schemaVersion, 1)
        XCTAssertEqual(
            artifact.diagnosticKind,
            "bitwardenRealPackageProductNormalTabAsyncExperiment"
        )
        XCTAssertEqual(artifact.packageSource, .realLocalUnpacked)
        XCTAssertEqual(artifact.packagePath, target.explicitAllowedLocalRoot)
        XCTAssertEqual(artifact.manifestVersion, "2026.4.1")
        XCTAssertEqual(
            artifact.manifestHash,
            "e3af5e1631fea87fb5ec1bf80a0d52a08411152bf12f121dd54c5feb5804a3dc"
        )
        XCTAssertEqual(
            artifact.sourceHash,
            "7d3a88b4b1b8ae882a20ba4decd2df6fc9859c72fe1e7d3a5a60eabb6e7d5d8e"
        )
        XCTAssertEqual(artifact.sourceHash, artifact.generatedHash)
        XCTAssertEqual(
            artifact.reviewedHashSelected,
            ChromeMV3LocalExperimentalProductNormalTabExperimentPolicy
                .reviewedBitwardenBootstrapAutofillSHA256
        )
        XCTAssertEqual(
            artifact.previousReviewedHashRetained,
            "89b0c2ce4d57431ddbfc8a28992ddf2cd36f2d2bbe64657c89bc164c76fe2b58"
        )
        XCTAssertTrue(artifact.sourceGeneratedByteEqual)
        XCTAssertTrue(artifact.hashGatePassed)
        XCTAssertEqual(artifact.fixtureResult.resultScope, "fixtureBaseline")
        XCTAssertEqual(
            artifact.realPackageResult.resultScope,
            "realLocalPackageProductNormalTabExperiment"
        )
        XCTAssertTrue(artifact.fixtureAndRealPackageResultsSeparated)
        XCTAssertTrue(artifact.realPackageResult.attempted)
        XCTAssertTrue(artifact.realPackageResult.allowed)
        XCTAssertTrue(artifact.realPackageResult.blockers.isEmpty)
        XCTAssertTrue(artifact.realPackageResult.webKitObjectCreationOccurred)
        XCTAssertEqual(
            artifact.realPackageResult.webKitObjectCreationStatus,
            "createdAfterHashGate"
        )
        XCTAssertTrue(artifact.realPackageResult.reviewedScriptExecuted)
        XCTAssertEqual(
            artifact.realPackageResult.reviewedScriptExecutionStatus,
            "executed"
        )
        XCTAssertEqual(
            artifact.realPackageResult.syntheticURL,
            "https://sumi.local.test/login"
        )
        XCTAssertEqual(
            artifact.realPackageResult.domBefore.usernameValueMarker,
            "empty"
        )
        XCTAssertEqual(
            artifact.realPackageResult.domAfter.usernameValueMarker,
            "syntheticDummyMatched"
        )
        XCTAssertEqual(
            artifact.realPackageResult.domAfter.passwordValueMarker,
            "syntheticDummyMatched"
        )
        XCTAssertTrue(artifact.realPackageResult.dummyMarkersOnly)
        XCTAssertEqual(
            artifact.realPackageResult.touchedSyntheticFields,
            [
                "sumi-login-email",
                "sumi-login-password",
            ]
        )
        XCTAssertTrue(artifact.realPackageResult.teardownCompleted)
        XCTAssertEqual(
            artifact.realPackageResult.retainedObjectCountAfterTeardown,
            0
        )
        XCTAssertFalse(
            artifact.runtimeFlags
                .productNormalTabExperimentAvailableByDefault
        )
        XCTAssertFalse(artifact.runtimeFlags.productDefaultRuntimeAvailable)
        XCTAssertFalse(artifact.runtimeFlags.productRuntimeAvailable)
        XCTAssertFalse(artifact.runtimeFlags.productRuntimeExposed)
        XCTAssertTrue(artifact.runtimeFlags.actionExplicitOnly)
        XCTAssertFalse(artifact.runtimeFlags.managerReadoutExecutedExperiment)
        XCTAssertFalse(artifact.runtimeFlags.arbitraryScriptingEnabled)
        XCTAssertFalse(artifact.runtimeFlags.mainWorldEnabled)
        XCTAssertFalse(artifact.runtimeFlags.multiFrameEnabled)
        XCTAssertFalse(artifact.runtimeFlags.fileSchemeEnabled)
        XCTAssertFalse(
            artifact.runtimeFlags.aboutBlankOrOriginFallbackEnabled
        )
        XCTAssertFalse(artifact.runtimeFlags.networkAuthNativeHostEnabled)
        XCTAssertFalse(artifact.runtimeFlags.timersOrPollingEnabled)
        XCTAssertFalse(artifact.runtimeFlags.backgroundWorkScheduled)
        XCTAssertFalse(artifact.runtimeFlags.permanentRuntimeRetained)
        XCTAssertTrue(artifact.disabledRuntimeInvariantPassed)
        XCTAssertTrue(artifact.protonRegressionSummary?.passed == true)
        XCTAssertTrue(
            artifact.onePasswordBlockedSummary?
                .nextBlockerClassification == "moduleWorkerUnsupported"
        )
        XCTAssertTrue(artifact.onePasswordBlockedSummary?.passed == true)
        XCTAssertTrue(artifact.noRealSecrets)
        XCTAssertTrue(artifact.noRawCredentials)
        XCTAssertTrue(artifact.notProductSupportLabel.contains(
            "not product support"
        ))
        XCTAssertFalse(artifactString.contains("sumi-test-user@example.test"))
        XCTAssertFalse(artifactString.contains("sumi-test-password-not-secret"))
        XCTAssertFalse(artifactString.contains("masterPassword"))
        XCTAssertFalse(artifactString.contains("accessToken"))
        XCTAssertFalse(artifactString.contains("refreshToken"))
        XCTAssertTrue(detectFill.modeledDummyFillChangedDOM)
        XCTAssertEqual(
            detectFill.domObservationAfter.usernameValue,
            "sumi-test-user@example.test"
        )
        XCTAssertEqual(
            detectFill.domObservationAfter.passwordValue,
            "sumi-test-password-not-secret"
        )
        XCTAssertTrue(
            detectFill.nextBlocker.contains("stable product normal-tab")
                || detectFill.nextBlocker
                    .contains("blockedByMissingReviewedResource")
        )
    }

    func testReviewedResolverBlocksTraversalAbsoluteRemoteFileAndSymlinkPaths()
        throws
    {
        let fixture = try makeFixture()
        let generatedBundle = fixture.modeledRequest().generatedBundle
        assertBlocked(
            "../content/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .unsafeScriptPath
        )
        assertBlocked(
            "/content/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .unsafeScriptPath
        )
        assertBlocked(
            "https://example.test/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .remoteScriptBlocked
        )
        assertBlocked(
            "file:///tmp/bootstrap-autofill.js",
            generatedBundle: generatedBundle,
            blocker: .fileSchemeScriptBlocked
        )

        let symlink = fixture.generated
            .appendingPathComponent("content/symlink.js")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL:
                fixture.generated
                .appendingPathComponent("content/bootstrap-autofill.js")
        )
        let symlinkBundle =
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
                recordAvailable: true,
                rootPath: fixture.generated.path,
                copiedResourcePaths: ["content/symlink.js"]
            )
        assertBlocked(
            "content/symlink.js",
            generatedBundle: symlinkBundle,
            blocker: .generatedResourceSymbolicLink
        )
    }

    func testSourceGuardsKeepAdapterSyntheticScopedAndEventDriven() throws {
        let source = try String(
            contentsOf:
                projectRoot().appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "chrome.scripting." + "executeScript",
            "function" + "Source",
            "\"MA" + "IN\"",
            "allFrames: " + "true",
            "fileSchemeAllowed: " + "true",
            "productNormalTabAllowed: " + "true",
            "productDefaultRuntimeAvailable: " + "true",
            "URL" + "Session",
            "WKWebExtension" + "Context(",
            "webExtension" + "Controller",
            "connect" + "Native",
            "Process" + "(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer(",
            "poll" + "ing",
            "chrome.webstore" + ".install",
            "clients2.google.com/service/update2/crx",
            "master" + "Password",
            "access" + "Token",
            "refresh" + "Token",
            "evaluateJavaScript(request",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertTrue(source.contains("WKWebsiteDataStore.nonPersistent()"))
        XCTAssertTrue(source.contains("WKContentWorld.world(name: contentWorldName)"))
        XCTAssertTrue(source.contains("frameIDs != [0]"))
        XCTAssertTrue(source.contains("sumiIsNormalTabWebViewConfiguration = true"))
        XCTAssertTrue(
            source.contains(
                "removeScriptMessageHandler(\n            forName: completionMessageHandlerName,\n            contentWorld: contentWorld"
            )
        )
    }

    private func assertBlocked(
        _ path: String,
        generatedBundle:
            ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle,
        blocker: ChromeMV3LocalExperimentalProgrammaticInjectionBlocker
    ) {
        let result =
            ChromeMV3LocalExperimentalProgrammaticInjectionSession
            .resolveGeneratedBundleFile(
                path,
                generatedBundle: generatedBundle
            )
        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(
            result.blockers.contains(blocker),
            "\(path): \(result.blockers)"
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("package", isDirectory: true)
        let generated =
            root.appendingPathComponent("generated", isDirectory: true)
        try write(
            "chrome.scripting.executeScript({files:['content/bootstrap-autofill.js']}); triggerAutofillScriptInjection();",
            to: package.appendingPathComponent("background.js")
        )
        try write(
            "autofill-injected-script-port",
            to:
                package.appendingPathComponent(
                    "content/content-message-handler.js"
                )
        )
        try write(
            reviewedFixtureScript,
            to:
                package.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        try write(
            reviewedFixtureScript,
            to:
                generated.appendingPathComponent(
                    "content/bootstrap-autofill.js"
                )
        )
        try write(
            "not reviewed",
            to: generated.appendingPathComponent("content/not-reviewed.js")
        )
        return Fixture(package: package, generated: generated)
    }

    private func makeSyntheticFixture() throws -> Fixture {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("package", isDirectory: true)
        let generated =
            root.appendingPathComponent("generated", isDirectory: true)
        try write(
            "chrome.scripting.executeScript({files:['content/sumi-reviewed-resource-marker.js']});",
            to: package.appendingPathComponent("background.js")
        )
        try write(
            syntheticReviewedResourceMarkerScript,
            to:
                package.appendingPathComponent(
                    "content/sumi-reviewed-resource-marker.js"
                )
        )
        try write(
            syntheticReviewedResourceMarkerScript,
            to:
                generated.appendingPathComponent(
                    "content/sumi-reviewed-resource-marker.js"
                )
        )
        try write(
            "not reviewed",
            to: generated.appendingPathComponent("content/not-reviewed.js")
        )
        return Fixture(
            package: package,
            generated: generated,
            reviewedResourcePath: "content/sumi-reviewed-resource-marker.js"
        )
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private struct Fixture {
        var package: URL
        var generated: URL
        var reviewedResourcePath: String = "content/bootstrap-autofill.js"

        func modeledRequest()
            -> ChromeMV3LocalExperimentalProgrammaticInjectionRequest
        {
            ChromeMV3LocalExperimentalProgrammaticInjectionRequest(
                moduleState: .enabled,
                localExperimentalGateAllowed: true,
                extensionEnabled: true,
                profileScopedExtensionLoaded: true,
                generatedBundle:
                    ChromeMV3LocalExperimentalProgrammaticInjectionGeneratedBundle(
                        recordAvailable: true,
                        rootPath: generated.path,
                        copiedResourcePaths: [
                            reviewedResourcePath,
                            "content/not-reviewed.js",
                        ]
                    ),
                packageRootPath: package.path,
                targetURL: "https://sumi.local.test/login",
                syntheticLoginURL: "https://sumi.local.test/login",
                tabID: 1,
                frameIDs: [0],
                allFrames: false,
                world: "ISOLATED",
                files: [reviewedResourcePath],
                functionSource: nil,
                arguments: [],
                injectImmediately: true,
                hostPermissionOrActiveTabAllowed: true
            )
        }

        func adapterRequest()
            -> ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest
        {
            let attempt =
                ChromeMV3LocalExperimentalProgrammaticInjectionSession()
                .attempt(modeledRequest())
            return ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest(
                moduleState: .enabled,
                localExperimentalGateAllowed: true,
                extensionEnabled: true,
                profileScopedExtensionLoaded: true,
                hostPermissionOrActiveTabAllowed: true,
                targetURL: "https://sumi.local.test/login",
                syntheticLoginURL: "https://sumi.local.test/login",
                documentID: "sumi-webkit-adapter-login-main-frame",
                navigationSequence: 1,
                frameIDs: [0],
                allFrames: false,
                world: "ISOLATED",
                dummyUsername: "sumi-test-user@example.test",
                dummyPassword: "sumi-test-password-not-secret",
                modeledInjectionAttempt: attempt
            )
        }

        func manualSmokeRequest(
            moduleEnabled: Bool = true,
            extensionEnabled: Bool = true,
            profileEnabled: Bool = true,
            localExperimentalProductGateAllowed: Bool = true,
            runtimeGateAllowsReadiness: Bool = true,
            contentScriptRouteReady: Bool = true,
            serviceWorkerRouteReady: Bool = true,
            tabSurface: ChromeMV3WebViewSurface = .normalTab,
            urlString: String = "https://sumi.local.test/login",
            hostPermissions: [String] = ["https://sumi.local.test/*"],
            frameID: Int = 0,
            isTopFrame: Bool = true,
            contentWorld: ChromeMV3ContentScriptWorld = .isolated,
            reviewedResourcePresent: Bool = true,
            productDefaultRuntimeAvailable: Bool = false,
            matchAboutBlank: Bool = false,
            matchOriginAsFallback: Bool = false
        ) -> ChromeMV3LocalExperimentalNormalTabManualSmokeRequest {
            var modeled = modeledRequest()
            modeled.targetURL = urlString
            modeled.syntheticLoginURL = urlString
            modeled.hostPermissionOrActiveTabAllowed =
                hostPermissions.isEmpty == false
            modeled.frameIDs = [frameID]
            modeled.world = contentWorld.rawValue
            let attempt =
                reviewedResourcePresent
                    ? ChromeMV3LocalExperimentalProgrammaticInjectionSession()
                        .attempt(modeled)
                    : ChromeMV3LocalExperimentalProgrammaticInjectionSession()
                        .attempt({
                            var missing = modeled
                            missing.files = ["content/not-reviewed.js"]
                            return missing
                        }())
            let broker = ChromeMV3PermissionBroker(
                state: ChromeMV3PermissionBrokerState(
                    extensionID: "manual-smoke-extension",
                    profileID: "manual-smoke-profile",
                    hostPermissions: hostPermissions
                )
            )
            let generatedResourceSHA256 =
                attempt.shapeAudit.reviewedResourceAudit?
                .generatedResourceSHA256
                    ?? attempt.shapeAudit.reviewedBootstrapSHA256
            let resource = ChromeMV3ProductNormalTabReviewedResource(
                reviewedScriptPath: reviewedResourcePath,
                generatedResourceHash:
                    reviewedResourcePresent
                        ? generatedResourceSHA256
                        : nil,
                generatedResourceFileSystemPath:
                    reviewedResourcePresent
                        ? attempt.resourceResolutions.first?
                            .resolvedFileSystemPath
                        : nil,
                present:
                    reviewedResourcePresent
                        && attempt.resourceResolutions.first?.status
                            == .copiedGeneratedBundleFile,
                packageOwned:
                    reviewedResourcePresent
                        && attempt.resourceResolutions.first?.status
                            == .copiedGeneratedBundleFile,
                diagnostics: attempt.resourceResolutions
                    .flatMap(\.diagnostics)
            )
            let preflight =
                ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                    input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                        profileID: "manual-smoke-profile",
                        extensionID: "manual-smoke-extension",
                        tabID: "1",
                        documentID: "manual-smoke-document",
                        urlString: urlString,
                        moduleEnabled: moduleEnabled,
                        extensionEnabled: extensionEnabled,
                        profileEnabled: profileEnabled,
                        localExperimentalProductGateAllowed:
                            localExperimentalProductGateAllowed,
                        runtimeGateAllowsReadiness:
                            runtimeGateAllowsReadiness,
                        contentScriptRouteReady: contentScriptRouteReady,
                        serviceWorkerRouteReady: serviceWorkerRouteReady,
                        tabSurface: tabSurface,
                        syntheticHTTPSOrigin: "https://sumi.local.test",
                        frameID: frameID,
                        isTopFrame: isTopFrame,
                        contentWorld: contentWorld,
                        hostAccessDecision:
                            broker.hostAccessDecision(
                                url: urlString,
                                tabID: 1
                            ),
                        reviewedResource: resource,
                        teardownPending: false
                    )
                )
            let plan =
                ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
                    preflight: preflight
                )
            return ChromeMV3LocalExperimentalNormalTabManualSmokeRequest(
                preflight: preflight,
                injectionPlan: plan,
                modeledInjectionAttempt: attempt,
                dummyUsername: "sumi-test-user@example.test",
                dummyPassword: "sumi-test-password-not-secret",
                productDefaultRuntimeAvailable:
                    productDefaultRuntimeAvailable,
                matchAboutBlank: matchAboutBlank,
                matchOriginAsFallback: matchOriginAsFallback
            )
        }
    }

    private var reviewedFixtureScript: String {
        """
        (() => {
          let listener;
          listener = (message, sender, sendResponse) => {
            if (message.command === "collectPageDetailsImmediately") {
              document.getElementById("sumi-login-email").opid = "__0";
              document.getElementById("sumi-login-password").opid = "__1";
              sendResponse({ fields: ["__0", "__1"] });
              return true;
            }
            if (message.command === "fillForm") {
              for (const [action, opid, value] of message.fillScript.script) {
                if (action !== "fill_by_opid") continue;
                const field = Array.from(document.querySelectorAll("input"))
                  .find((item) => item.opid === opid);
                if (field) field.value = value;
              }
              sendResponse(null);
              return true;
            }
            return null;
          };
          chrome.runtime.onMessage.addListener(listener);
          chrome.runtime.connect({ name: "autofill-injected-script-port" });
          window.bitwardenAutofillInit = {
            destroy() { chrome.runtime.onMessage.removeListener(listener); }
          };
        })();
        """
    }

    private var syntheticReviewedResourceMarkerScript: String {
        """
        (() => {
          const marker = globalThis.__sumiSyntheticReviewedResourceMarker || {};
          const username = document.getElementById("sumi-login-email");
          const password = document.getElementById("sumi-login-password");
          if (username && typeof marker.username === "string") {
            username.value = marker.username;
            username.dataset.sumiReviewedResourceMarker = "username";
          }
          if (password && typeof marker.password === "string") {
            password.value = marker.password;
            password.dataset.sumiReviewedResourceMarker = "password";
          }
          globalThis.__sumiSyntheticReviewedResourceDiagnostic = {
            fixture: "sumiSyntheticReviewedResource",
            touched: [
              username ? username.id : "missing-username",
              password ? password.id : "missing-password"
            ],
            destroy() {
              delete globalThis.__sumiSyntheticReviewedResourceDiagnostic;
              delete globalThis.__sumiSyntheticReviewedResourceMarker;
            }
          };
        })();
        """
    }
}
#endif
