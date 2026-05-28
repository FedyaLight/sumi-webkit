import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ReadinessFixturePipelineTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testPipelineGeneratesContextReadinessReportUnderExplicitTempRoot()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let pipelineRoot = try makeTemporaryDirectory()
        let result = try await makePipeline().run(
            candidateID: "generated-valid",
            rootURL: pipelineRoot
        )
        let contextReportURL = try XCTUnwrap(result.contextReadinessReportURL)
        let objectReportURL = try XCTUnwrap(result.objectAcceptanceReportURL)
        let contextReport = try XCTUnwrap(result.contextReadinessReport)
        let consumer = try XCTUnwrap(result.consumerDiagnostic)

        XCTAssertTrue(
            contextReportURL.path.hasPrefix(pipelineRoot.path),
            contextReportURL.path
        )
        XCTAssertTrue(
            contextReportURL.path.contains(
                "/ChromeMV3ReadinessPipeline/generated-valid/"
            ),
            contextReportURL.path
        )
        XCTAssertTrue(
            contextReportURL.path.hasSuffix(
                "/generated-rewritten/context-readiness-report.json"
            ),
            contextReportURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: objectReportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextReportURL.path))
        XCTAssertEqual(consumer.state, .ready)
        XCTAssertTrue(consumer.canImplementRecommendedBranch)
        XCTAssertEqual(
            consumer.nextRequiredPromptCategory,
            contextReport.nextRequiredPromptCategory
        )
        XCTAssertEqual(
            contextReport.nextRequiredPromptCategory,
            .addRuntimeBridgePrerequisites
        )
        XCTAssertFalse(contextReport.runtimeLoadable)
        XCTAssertFalse(contextReport.canLoadContextNow)
        XCTAssertEqual(result.runtimeLoadabilityReport?.runtimeLoadable, false)
    }

    @MainActor
    func testPipelineDoesNotRelyOnRepositoryRootArtifactSearch()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let pipelineRoot = try makeTemporaryDirectory()
        let poisonRoot = try makeTemporaryDirectory()
        let poisonReportURL = poisonRoot.appendingPathComponent(
            ChromeMV3ContextReadinessReportWriter.reportFileName
        )
        try Data("{".utf8).write(to: poisonReportURL)

        let result = try await makePipeline().run(
            candidateID: "explicit-root-only",
            rootURL: pipelineRoot
        )

        XCTAssertEqual(result.consumerDiagnostic?.state, .ready)
        XCTAssertNotEqual(result.contextReadinessReportURL, poisonReportURL)
        XCTAssertTrue(
            result.contextReadinessReportURL?.path.hasPrefix(pipelineRoot.path)
                == true
        )
        XCTAssertFalse(
            result.contextReadinessReportURL?.path.hasPrefix(poisonRoot.path)
                == true
        )
    }

    @MainActor
    func testDisabledModuleDoesNotGenerateOrConsumeReport()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let pipelineRoot = try makeTemporaryDirectory()
        let result = try await makePipeline().run(
            candidateID: "disabled-module",
            rootURL: pipelineRoot,
            extensionsModuleEnabled: false
        )

        XCTAssertTrue(result.disabledByModule)
        XCTAssertNil(result.objectAcceptanceReportURL)
        XCTAssertNil(result.contextReadinessReportURL)
        XCTAssertNil(result.runtimeBridgePrerequisitesReportURL)
        XCTAssertNil(result.runtimeBridgeReadinessReportURL)
        XCTAssertNil(result.consumerDiagnostic)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: pipelineRoot
                    .appendingPathComponent("ChromeMV3ReadinessPipeline")
                    .appendingPathComponent("disabled-module")
                    .appendingPathComponent("generated-rewritten")
                    .appendingPathComponent(
                        ChromeMV3ContextReadinessReportWriter.reportFileName
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: pipelineRoot
                    .appendingPathComponent("ChromeMV3ReadinessPipeline")
                    .appendingPathComponent("disabled-module")
                    .appendingPathComponent("generated-rewritten")
                    .appendingPathComponent(
                        ChromeMV3RuntimeBridgeReadinessReportWriter
                            .reportFileName
                    )
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: pipelineRoot
                    .appendingPathComponent("ChromeMV3ReadinessPipeline")
                    .appendingPathComponent("disabled-module")
                    .appendingPathComponent("generated-rewritten")
                    .appendingPathComponent(
                        ChromeMV3RuntimeBridgePrerequisitesReportWriter
                            .reportFileName
                    )
                    .path
            )
        )
    }

    @MainActor
    func testObjectAcceptanceFailureSelectsDiagnosticOnlyBranch()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "object-rejected",
            rootURL: try makeTemporaryDirectory(),
            objectProbeMode: .syntheticFailure
        )
        let report = try XCTUnwrap(result.contextReadinessReport)
        let consumer = try XCTUnwrap(result.consumerDiagnostic)

        XCTAssertFalse(report.objectAcceptedByWebKit)
        XCTAssertFalse(report.futureContextEligible)
        XCTAssertEqual(report.nextRequiredPromptCategory, .fixObjectAcceptance)
        XCTAssertEqual(consumer.state, .ready)
        XCTAssertEqual(consumer.nextRequiredPromptCategory, .fixObjectAcceptance)
        let plan = ChromeMV3RuntimeBridgePrerequisitePlanner.plan(
            report: report,
            consumptionDiagnostic: consumer
        )
        XCTAssertFalse(plan.canRecordPrerequisitesNow)
        XCTAssertTrue(
            plan.blockingReasons.contains {
                $0.contains("did not select addRuntimeBridgePrerequisites")
            }
        )
    }

    @MainActor
    func testGeneratedBranchImplementationFollowsOnlyGeneratedCategory()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "branch-following",
            rootURL: try makeTemporaryDirectory()
        )
        let report = try XCTUnwrap(result.contextReadinessReport)
        let consumer = try XCTUnwrap(result.consumerDiagnostic)
        let plan = ChromeMV3RuntimeBridgePrerequisitePlanner.plan(
            report: report,
            consumptionDiagnostic: consumer
        )

        if report.nextRequiredPromptCategory == .addRuntimeBridgePrerequisites {
            XCTAssertTrue(plan.canRecordPrerequisitesNow)
            XCTAssertEqual(
                plan.branchImplemented,
                .addRuntimeBridgePrerequisites
            )
        } else {
            XCTAssertFalse(plan.canRecordPrerequisitesNow)
            XCTAssertTrue(
                plan.blockingReasons.contains {
                    $0.contains("did not select addRuntimeBridgePrerequisites")
                }
            )
        }
        XCTAssertFalse(plan.canLoadContextNow)
        XCTAssertFalse(plan.runtimeLoadable)
        XCTAssertFalse(plan.contextCreationAllowed)
        XCTAssertFalse(plan.controllerLoadAllowed)
    }

    @MainActor
    func testGeneratedRuntimeBridgePrerequisitePlanIsNonExecuting()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-prerequisites",
            rootURL: try makeTemporaryDirectory()
        )
        let report = try XCTUnwrap(result.contextReadinessReport)
        let consumer = try XCTUnwrap(result.consumerDiagnostic)

        XCTAssertEqual(
            report.nextRequiredPromptCategory,
            .addRuntimeBridgePrerequisites
        )
        let plan = ChromeMV3RuntimeBridgePrerequisitePlanner.plan(
            report: report,
            consumptionDiagnostic: consumer
        )

        XCTAssertTrue(plan.canRecordPrerequisitesNow)
        XCTAssertEqual(plan.branchImplemented, .addRuntimeBridgePrerequisites)
        XCTAssertTrue(
            plan.prerequisites.contains {
                $0.category == .runtimeMessaging && $0.required
            }
        )
        XCTAssertTrue(
            plan.prerequisites.contains {
                $0.category == .nativeMessaging && $0.required
            }
        )
        XCTAssertTrue(plan.prerequisites.allSatisfy(\.nonExecuting))
        XCTAssertFalse(plan.contextCreationAllowed)
        XCTAssertFalse(plan.controllerLoadAllowed)
        XCTAssertFalse(plan.extensionCodeExecutionAllowed)
        XCTAssertFalse(plan.userScriptRegistrationAllowed)
        XCTAssertFalse(plan.nativeMessagingLaunchAllowed)
        XCTAssertFalse(plan.runtimeLoadable)
        XCTAssertFalse(plan.canLoadContextNow)
    }

    @MainActor
    func testPipelineWritesRuntimeBridgePrerequisitesReportUnderExplicitTempRoot()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let pipelineRoot = try makeTemporaryDirectory()
        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-report",
            rootURL: pipelineRoot
        )
        let reportURL = try XCTUnwrap(
            result.runtimeBridgePrerequisitesReportURL
        )
        let report = try XCTUnwrap(
            result.runtimeBridgePrerequisitesReport
        )

        XCTAssertTrue(reportURL.path.hasPrefix(pipelineRoot.path))
        XCTAssertTrue(
            reportURL.path.hasSuffix(
                "/generated-rewritten/runtime-bridge-prerequisites-report.json"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        XCTAssertEqual(report.candidateID, result.contextReadinessReport?.candidateID)
        XCTAssertEqual(report.contextReadinessReportHash.count, 64)
        XCTAssertEqual(
            report.nextRequiredCategoryAfterThisReport,
            .implementRuntimeBridgeComponents
        )
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testRuntimeBridgePrerequisitesReportModelsContractsWithoutRuntime()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-contracts",
            rootURL: try makeTemporaryDirectory()
        )
        let report = try XCTUnwrap(
            result.runtimeBridgePrerequisitesReport
        )

        XCTAssertFalse(report.runtimeMessagingPrerequisites.implementedNow)
        XCTAssertFalse(report.runtimeMessagingPrerequisites.dispatchImplemented)
        XCTAssertFalse(
            report.runtimeMessagingPrerequisites.listenerDeliveryImplemented
        )
        XCTAssertTrue(
            report.runtimeMessagingPrerequisites
                .requiredBeforePasswordManagerSupport
        )
        XCTAssertTrue(
            report.runtimeMessagingPrerequisites
                .requiredBeforeRuntimeLoadability
        )
        XCTAssertTrue(
            report.runtimeMessagingPrerequisites.routes.contains {
                $0.requiredAPI == "runtime.sendMessage"
            }
        )

        XCTAssertTrue(
            report.nativeMessagingPrerequisites.nativeMessagingDetected
        )
        XCTAssertTrue(
            report.nativeMessagingPrerequisites.nativeMessagingBlocked
        )
        XCTAssertTrue(
            report.nativeMessagingPrerequisites.hostValidationImplemented
        )
        XCTAssertFalse(
            report.nativeMessagingPrerequisites.processLaunchImplemented
        )
        XCTAssertTrue(
            report.nativeMessagingPrerequisites
                .requiredBeforePasswordManagerSupport
        )

        let storageAreas = Dictionary(
            uniqueKeysWithValues: report.storagePrerequisites.areas.map {
                ($0.area, $0)
            }
        )
        XCTAssertEqual(storageAreas[.local]?.required, true)
        XCTAssertEqual(storageAreas[.session]?.required, true)
        XCTAssertEqual(storageAreas[.sync]?.required, true)
        XCTAssertFalse(report.storagePrerequisites.implementedNow)
        XCTAssertTrue(
            report.storagePrerequisites.hostBackedLayerDecisionRequired
        )

        XCTAssertTrue(
            report.permissionsActiveTabPrerequisites
                .permissionBrokerImplemented
        )
        XCTAssertTrue(
            report.permissionsActiveTabPrerequisites.activeTabImplemented
        )
        XCTAssertTrue(
            report.permissionsActiveTabPrerequisites
                .hostPermissionEvaluationImplemented
        )
        XCTAssertTrue(
            report.permissionsActiveTabPrerequisites
                .requiredBeforeContentScriptExecution
        )

        XCTAssertTrue(
            report.serviceWorkerLifecyclePrerequisites
                .lifecycleCoordinatorImplemented
        )
        XCTAssertFalse(
            report.serviceWorkerLifecyclePrerequisites
                .serviceWorkerWakeImplemented
        )
        XCTAssertTrue(
            report.serviceWorkerLifecyclePrerequisites
                .idleUnloadPolicyModeled
        )
        XCTAssertTrue(
            report.serviceWorkerLifecyclePrerequisites
                .permanentBackgroundForbidden
        )
        XCTAssertTrue(
            report.serviceWorkerLifecyclePrerequisites
                .requiredBeforeContextLoad
        )
        XCTAssertTrue(
            report.serviceWorkerLifecyclePrerequisites
                .requiredBeforeRuntimeLoadability
        )

        let password = report.passwordManagerPrerequisiteSummary
        XCTAssertTrue(password.contentScriptsPresent)
        XCTAssertTrue(password.actionPopupPresent)
        XCTAssertTrue(password.hostPermissionsPresent)
        XCTAssertTrue(password.storagePermissionPresent)
        XCTAssertTrue(password.nativeMessagingPermissionPresent)
        XCTAssertTrue(password.runtimeMessagingMissing)
        XCTAssertTrue(password.permissionActiveTabMissing)
        XCTAssertTrue(password.storageBackendMissingOrDeferred)
        XCTAssertTrue(password.nativeMessagingMissing)
        XCTAssertTrue(password.controlledInputPageWorldBehaviorNotVerified)
        XCTAssertTrue(password.serviceWorkerLifecycleNotVerified)
        XCTAssertFalse(password.passwordManagerSupportReady)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)

        let messagingReport = try XCTUnwrap(
            result.runtimeMessagingContractReport
        )
        let listenerReport = try XCTUnwrap(
            result.runtimeListenerContractReport
        )
        XCTAssertEqual(
            Set(messagingReport.routeContractCoverage.map(\.routeKind)),
            Set(ChromeMV3RuntimeMessagingRouteKind.allCases)
        )
        XCTAssertFalse(messagingReport.canDispatchMessagesNow)
        XCTAssertFalse(messagingReport.canRegisterListenersNow)
        XCTAssertFalse(messagingReport.canWakeServiceWorkerNow)
        XCTAssertFalse(messagingReport.canOpenPortNow)
        XCTAssertFalse(messagingReport.canCreateContextNow)
        XCTAssertFalse(messagingReport.canLoadContextNow)
        XCTAssertFalse(messagingReport.runtimeLoadable)
        XCTAssertFalse(
            messagingReport.passwordManagerMessagingSummary
                .passwordManagerMessagingReady
        )

        XCTAssertEqual(
            Set(listenerReport.listenerSurfaceCoverage.map(\.surface)),
            Set(ChromeMV3RuntimeListenerSurfaceKind.allCases)
        )
        XCTAssertFalse(listenerReport.canRegisterListenersNow)
        XCTAssertFalse(listenerReport.canResolveReceivingListenersNow)
        XCTAssertFalse(listenerReport.canDispatchMessagesNow)
        XCTAssertFalse(listenerReport.canWakeServiceWorkerNow)
        XCTAssertFalse(listenerReport.canCreateContextNow)
        XCTAssertFalse(listenerReport.canLoadContextNow)
        XCTAssertFalse(listenerReport.runtimeLoadable)
        XCTAssertFalse(
            listenerReport.passwordManagerListenerSummary
                .passwordManagerListenerReady
        )
    }

    @MainActor
    func testPipelineWritesRuntimeBridgeReadinessReportUnderExplicitTempRoot()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let pipelineRoot = try makeTemporaryDirectory()
        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-readiness",
            rootURL: pipelineRoot
        )
        let reportURL = try XCTUnwrap(
            result.runtimeBridgeReadinessReportURL
        )
        let report = try XCTUnwrap(
            result.runtimeBridgeReadinessReport
        )

        XCTAssertTrue(reportURL.path.hasPrefix(pipelineRoot.path))
        XCTAssertTrue(
            reportURL.path.hasSuffix(
                "/generated-rewritten/runtime-bridge-readiness-report.json"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3RuntimeBridgeReadinessReportWriter.reportFileName
        )
        XCTAssertEqual(
            report.prerequisiteReportID,
            result.runtimeBridgePrerequisitesReport?.id
        )
        XCTAssertEqual(report.prerequisiteReportHash.count, 64)
        XCTAssertEqual(
            report.nextRequiredCategory,
            .diagnosticRuntimePrerequisite
        )
        XCTAssertEqual(
            report.runtimeMessagingContractReportSummary.reportFileName,
            ChromeMV3RuntimeMessagingContractReportWriter.reportFileName
        )
        XCTAssertEqual(
            report.runtimeListenerContractReportSummary?.reportFileName,
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
        )
        let listenerSummary = try XCTUnwrap(
            report.runtimeListenerContractReportSummary
        )
        XCTAssertFalse(
            report.runtimeMessagingContractReportSummary
                .canDispatchMessagesNow
        )
        XCTAssertFalse(listenerSummary.canRegisterListenersNow)
        XCTAssertFalse(
            report.runtimeMessagingContractReportSummary
                .passwordManagerMessagingReady
        )
        XCTAssertTrue(report.shouldFutureContextCreationRemainBlocked)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testRuntimeBridgeReadinessGatesRemainBlockedWithoutRuntime()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-gates",
            rootURL: try makeTemporaryDirectory()
        )
        let report = try XCTUnwrap(result.runtimeBridgeReadinessReport)

        XCTAssertEqual(report.messagingGate.status, .blocked)
        XCTAssertTrue(
            report.messagingGate.runtimeSendMessageContractDefined
        )
        XCTAssertTrue(
            report.messagingGate.tabsSendMessageContractDefined
        )
        XCTAssertTrue(
            report.messagingGate.runtimeConnectPortLifecycleContractDefined
        )
        XCTAssertTrue(
            report.messagingGate.disconnectErrorTimeoutPolicyDefined
        )
        XCTAssertTrue(
            report.messagingGate.callbackPromiseBridgingContractDefined
        )
        XCTAssertTrue(report.messagingGate.lastErrorPolicyDefined)
        XCTAssertTrue(
            report.messagingGate
                .contentScriptPopupServiceWorkerRouteContractsDefined
        )
        XCTAssertFalse(report.messagingGate.dispatchImplemented)
        XCTAssertFalse(report.messagingGate.listenerRegistrationImplemented)
        XCTAssertFalse(report.messagingGate.serviceWorkerWakeImplemented)
        XCTAssertFalse(report.messagingGate.messagingReadyForContextLoad)

        XCTAssertEqual(report.storageGate.status, .blocked)
        XCTAssertTrue(report.storageGate.extensionRequiresStorage)
        XCTAssertFalse(report.storageGate.storageRuntimeImplemented)
        XCTAssertFalse(report.storageGate.storageReadyForContextLoad)
        XCTAssertEqual(
            Set(report.storageGate.areas.map(\.area)),
            Set(ChromeMV3StorageAreaName.allCases)
        )
        XCTAssertTrue(
            report.storageGate.areas.allSatisfy {
                $0.status == .blocked && $0.readyForContextLoad == false
            }
        )

        XCTAssertEqual(report.permissionsActiveTabGate.status, .blocked)
        XCTAssertTrue(
            report.permissionsActiveTabGate
                .hostPermissionEvaluationRequired
        )
        XCTAssertTrue(
            report.permissionsActiveTabGate.activeTabGrantModelRequired
        )
        XCTAssertTrue(
            report.permissionsActiveTabGate.permissionBrokerImplemented
        )
        XCTAssertTrue(
            report.permissionsActiveTabGate.activeTabImplemented
        )
        XCTAssertTrue(
            report.permissionsActiveTabGate
                .hostPermissionEvaluationImplemented
        )
        XCTAssertFalse(
            report.permissionsActiveTabGate.permissionsReadyForContextLoad
        )

        XCTAssertEqual(report.nativeMessagingGate.status, .blocked)
        XCTAssertTrue(report.nativeMessagingGate.nativeMessagingDetected)
        XCTAssertTrue(report.nativeMessagingGate.nativeMessagingBlocked)
        XCTAssertTrue(
            report.nativeMessagingGate
                .nativeMessagingSafelyBlockedOrImplemented
        )
        XCTAssertFalse(
            report.nativeMessagingGate.nativeMessagingRuntimeImplemented
        )
        XCTAssertFalse(report.nativeMessagingGate.processLaunchImplemented)
        XCTAssertFalse(
            report.nativeMessagingGate.nativeMessagingReadyForContextLoad
        )

        XCTAssertEqual(report.serviceWorkerLifecycleGate.status, .blocked)
        XCTAssertTrue(report.serviceWorkerLifecycleGate.requiredForCandidate)
        XCTAssertTrue(
            report.serviceWorkerLifecycleGate.permanentBackgroundForbidden
        )
        XCTAssertTrue(
            report.serviceWorkerLifecycleGate
                .lifecycleCoordinatorImplemented
        )
        XCTAssertFalse(
            report.serviceWorkerLifecycleGate.serviceWorkerWakeImplemented
        )
        XCTAssertFalse(
            report.serviceWorkerLifecycleGate.lifecycleReadyForContextLoad
        )

        XCTAssertEqual(report.passwordManagerGate.status, .blocked)
        XCTAssertTrue(
            report.passwordManagerGate.passwordManagerLikeFixtureDetected
        )
        XCTAssertTrue(report.passwordManagerGate.contentScriptsDetected)
        XCTAssertTrue(report.passwordManagerGate.actionPopupDetected)
        XCTAssertTrue(report.passwordManagerGate.hostPermissionsDetected)
        XCTAssertTrue(report.passwordManagerGate.storagePermissionDetected)
        XCTAssertTrue(report.passwordManagerGate.nativeMessagingDetected)
        XCTAssertTrue(report.passwordManagerGate.runtimeMessagingMissing)
        XCTAssertTrue(report.passwordManagerGate.permissionsActiveTabMissing)
        XCTAssertTrue(report.passwordManagerGate.storageBackendMissing)
        XCTAssertTrue(report.passwordManagerGate.nativeMessagingMissing)
        XCTAssertTrue(report.passwordManagerGate.serviceWorkerLifecycleMissing)
        XCTAssertTrue(
            report.passwordManagerGate
                .controlledInputPageWorldBehaviorUnverified
        )
        XCTAssertFalse(report.passwordManagerGate.passwordManagerSupportReady)
    }

    @MainActor
    func testRuntimeBridgePrerequisitesReportIsDeterministic()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-deterministic",
            rootURL: try makeTemporaryDirectory()
        )
        let root = try XCTUnwrap(result.generatedRewrittenRootURL)
        let firstURL = try XCTUnwrap(result.runtimeBridgePrerequisitesReportURL)
        let firstData = try Data(contentsOf: firstURL)
        let second = try ChromeMV3RuntimeBridgePrerequisitesReportGenerator
            .makeReport(loadingContextReadinessReportFrom: root)
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(contentsOf: firstURL)

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(second, result.runtimeBridgePrerequisitesReport)
    }

    @MainActor
    func testRuntimeListenerContractReportIsDeterministic()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-listener-deterministic",
            rootURL: try makeTemporaryDirectory()
        )
        let root = try XCTUnwrap(result.generatedRewrittenRootURL)
        let firstURL = try XCTUnwrap(result.runtimeListenerContractReportURL)
        let firstData = try Data(contentsOf: firstURL)
        let second = try ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(loadingPrerequisitesReportFrom: root)
        try ChromeMV3RuntimeListenerContractReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(contentsOf: firstURL)

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(second, result.runtimeListenerContractReport)
    }

    @MainActor
    func testRuntimeBridgeReadinessReportIsDeterministic()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Readiness fixture pipeline requires macOS 15.5.")
        }

        let result = try await makePipeline().run(
            candidateID: "runtime-bridge-readiness-deterministic",
            rootURL: try makeTemporaryDirectory()
        )
        let root = try XCTUnwrap(result.generatedRewrittenRootURL)
        let firstURL = try XCTUnwrap(result.runtimeBridgeReadinessReportURL)
        let firstData = try Data(contentsOf: firstURL)
        let second = try ChromeMV3RuntimeBridgeReadinessReportGenerator
            .makeReport(loadingReportsFrom: root)
        try ChromeMV3RuntimeBridgeReadinessReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(contentsOf: firstURL)

        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(second, result.runtimeBridgeReadinessReport)
    }

    func testSourceGuardsForReadinessFixturePipelineAndRuntimeBridgeBranch()
        throws
    {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let chromeMV3ProductSourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let extensionCreationFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "(") }
            .map(\.relativePath)
            .sorted()
        XCTAssertEqual(
            extensionCreationFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let contextCreationFiles = sourceFiles
            .filter {
                $0.contents.contains("WKWebExtension" + "Context(")
            }
            .map(\.relativePath)
            .sorted()
        XCTAssertEqual(
            contextCreationFiles,
            []
        )

        let source = chromeMV3ProductSourceFiles
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
            "scheduled" + "Ti" + "mer",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerSupportReady\\s*[:=].*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                source.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private func makePipeline() -> ChromeMV3ReadinessFixturePipeline {
        ChromeMV3ReadinessFixturePipeline(
            temporaryDirectories: { [weak self] directory in
                self?.temporaryDirectories.append(directory)
            }
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
        return files.sorted(by: { lhs, rhs in
            lhs.relativePath < rhs.relativePath
        })
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum ChromeMV3ReadinessFixtureObjectProbeMode {
    case actual
    case syntheticFailure
}

private struct ChromeMV3ReadinessFixturePipelineResult {
    var disabledByModule: Bool
    var candidateRootURL: URL
    var sourceRootURL: URL?
    var storeRootURL: URL?
    var generatedRewrittenRootURL: URL?
    var objectAcceptanceReportURL: URL?
    var contextReadinessReportURL: URL?
    var runtimeBridgePrerequisitesReportURL: URL?
    var runtimeMessagingContractReportURL: URL?
    var runtimeListenerContractReportURL: URL?
    var runtimeBridgeReadinessReportURL: URL?
    var runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    var candidate: ChromeMV3RewrittenVariantCandidate?
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    var contextReadinessReport: ChromeMV3ContextReadinessReport?
    var runtimeBridgePrerequisitesReport:
        ChromeMV3RuntimeBridgePrerequisitesReport?
    var runtimeMessagingContractReport:
        ChromeMV3RuntimeMessagingContractReport?
    var runtimeListenerContractReport:
        ChromeMV3RuntimeListenerContractReport?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var consumerDiagnostic:
        ChromeMV3ContextReadinessReportConsumptionDiagnostic?
}

private final class ChromeMV3ReadinessFixturePipeline {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let fixedControllerIdentifier = UUID(
        uuidString: "00000000-0000-0000-0000-000000000021"
    )!
    private let temporaryDirectories: (URL) -> Void

    init(temporaryDirectories: @escaping (URL) -> Void) {
        self.temporaryDirectories = temporaryDirectories
    }

    @MainActor
    func run(
        candidateID: String,
        rootURL: URL,
        extensionsModuleEnabled: Bool = true,
        objectProbeMode: ChromeMV3ReadinessFixtureObjectProbeMode = .actual
    ) async throws -> ChromeMV3ReadinessFixturePipelineResult {
        let candidateRootURL = rootURL
            .appendingPathComponent(
                "ChromeMV3ReadinessPipeline",
                isDirectory: true
            )
            .appendingPathComponent(candidateID, isDirectory: true)
        if FileManager.default.fileExists(atPath: candidateRootURL.path) {
            try FileManager.default.removeItem(at: candidateRootURL)
        }
        try FileManager.default.createDirectory(
            at: candidateRootURL,
            withIntermediateDirectories: true
        )

        guard extensionsModuleEnabled else {
            return ChromeMV3ReadinessFixturePipelineResult(
                disabledByModule: true,
                candidateRootURL: candidateRootURL,
                sourceRootURL: nil,
                storeRootURL: nil,
                generatedRewrittenRootURL: nil,
                objectAcceptanceReportURL: nil,
                contextReadinessReportURL: nil,
                runtimeBridgePrerequisitesReportURL: nil,
                runtimeMessagingContractReportURL: nil,
                runtimeListenerContractReportURL: nil,
                runtimeBridgeReadinessReportURL: nil,
                runtimeLoadabilityReport: nil,
                candidate: nil,
                objectAcceptanceReport: nil,
                contextReadinessReport: nil,
                runtimeBridgePrerequisitesReport: nil,
                runtimeMessagingContractReport: nil,
                runtimeListenerContractReport: nil,
                runtimeBridgeReadinessReport: nil,
                consumerDiagnostic: nil
            )
        }

        let sourceRootURL = try writeSourceFixture(
            candidateRootURL: candidateRootURL
        )
        let storeRootURL = candidateRootURL
            .appendingPathComponent("fixture-store", isDirectory: true)
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRootURL,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: sourceRootURL)
        let generated = try ChromeMV3GeneratedBundleWriter(rootURL: storeRootURL)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let decoder = JSONDecoder()
        let runtimeResourcePlan = try decoder.decode(
            ChromeMV3RuntimeResourcePlan.self,
            from: Data(
                contentsOf: generated.generatedBundleRootURL
                    .appendingPathComponent("runtime-resource-plan.json")
            )
        )
        let preview = try decoder.decode(
            ChromeMV3ManifestRewritePreview.self,
            from: Data(contentsOf: generated.manifestRewritePreviewURL)
        )
        let dryRunReport = try decoder.decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            from: Data(contentsOf: generated.manifestRewriteDryRunReportURL)
        )
        let variant = try ChromeMV3GeneratedRewriteVariantWriter()
            .writeRewrittenVariant(
                generatedBundleRecord: generated.record,
                generatedBundleRootURL: generated.generatedBundleRootURL,
                runtimeResourcePlan: runtimeResourcePlan,
                manifestRewritePreview: preview,
                dryRunReport: dryRunReport
            )
        let runtimeReportURL = variant.variantRootURL
            .appendingPathComponent(
                ChromeMV3RuntimeLoadabilityVerifier.reportFileName
            )
        let runtimeReportData = try Data(contentsOf: runtimeReportURL)
        let runtimeReport = try decoder.decode(
            ChromeMV3RuntimeLoadabilityReport.self,
            from: runtimeReportData
        )
        let candidate = ChromeMV3RewrittenVariantCandidate(
            id: variant.report.id,
            generatedVariantRootPath: generated.generatedBundleRootURL.path,
            rewrittenVariantRootPath: variant.variantRootURL.path,
            runtimeLoadabilityReportPath: runtimeReportURL.path,
            rewrittenManifestSHA256: variant.report.rewrittenManifestSHA256,
            runtimeLoadabilityReportSHA256: sha256Hex(runtimeReportData),
            manifestVersion: 3,
            rewrittenVariantExists: true
        )
        let probeDecision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: objectProbeGateInput(
                candidate: candidate,
                runtimeReport: runtimeReport,
                extensionsModuleEnabled: extensionsModuleEnabled
            )
        )
        let probeDiagnostics =
            try await objectProbeDiagnostics(
                mode: objectProbeMode,
                decision: probeDecision
            )
        let objectReport =
            ChromeMV3WebKitObjectAcceptanceReportGenerator.makeReport(
                candidate: candidate,
                gateDecision: probeDecision,
                probeDiagnostics: probeDiagnostics,
                runtimeLoadabilityReport: runtimeReport
            )
        try ChromeMV3WebKitObjectAcceptanceReportWriter.write(
            objectReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )
        let emptyControllerOwner = try makeEmptyControllerOwner()
        let emptyControllerDiagnostics = emptyControllerOwner.diagnostics()
        emptyControllerOwner.tearDown()
        let contextReport =
            ChromeMV3ContextReadinessReportGenerator.makeReport(
                candidate: candidate,
                loadingObjectAcceptanceReportFrom: variant.variantRootURL,
                objectProbeDiagnostics: probeDiagnostics,
                emptyControllerDiagnostics: emptyControllerDiagnostics,
                runtimeLoadabilityReport: runtimeReport
            )
        try ChromeMV3ContextReadinessReportWriter.write(
            contextReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )
        let contextReportURL = variant.variantRootURL
            .appendingPathComponent(
                ChromeMV3ContextReadinessReportWriter.reportFileName
            )
        let consumer = ChromeMV3ContextReadinessReportConsumer.diagnostic(
            fromRewrittenBundleRoot: variant.variantRootURL
        )
        let contextReportData = try Data(contentsOf: contextReportURL)
        let runtimeBridgePrerequisitesReport =
            ChromeMV3RuntimeBridgePrerequisitesReportGenerator.makeReport(
                contextReadinessReport: contextReport,
                contextReadinessReportPath: contextReportURL.path,
                contextReadinessReportHash:
                    sha256Hex(contextReportData),
                consumptionDiagnostic: consumer
            )
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            runtimeBridgePrerequisitesReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )
        let runtimeMessagingContractReport =
            ChromeMV3RuntimeMessagingContractReportGenerator.makeReport(
                prerequisitesReport: runtimeBridgePrerequisitesReport
            )
        try ChromeMV3RuntimeMessagingContractReportWriter.write(
            runtimeMessagingContractReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )
        let runtimeListenerContractReport =
            ChromeMV3RuntimeListenerContractReportGenerator.makeReport(
                prerequisitesReport: runtimeBridgePrerequisitesReport,
                contextReadinessReport: contextReport
            )
        try ChromeMV3RuntimeListenerContractReportWriter.write(
            runtimeListenerContractReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )
        let runtimeBridgeReadinessReport =
            ChromeMV3RuntimeBridgeReadinessReportGenerator.makeReport(
                prerequisitesReport: runtimeBridgePrerequisitesReport,
                prerequisitesReportPath: variant.variantRootURL
                    .appendingPathComponent(
                        ChromeMV3RuntimeBridgePrerequisitesReportWriter
                            .reportFileName
                    )
                    .path,
                contextReadinessReport: contextReport
            )
        try ChromeMV3RuntimeBridgeReadinessReportWriter.write(
            runtimeBridgeReadinessReport,
            toRewrittenBundleRoot: variant.variantRootURL
        )

        return ChromeMV3ReadinessFixturePipelineResult(
            disabledByModule: false,
            candidateRootURL: candidateRootURL,
            sourceRootURL: sourceRootURL,
            storeRootURL: storeRootURL,
            generatedRewrittenRootURL: variant.variantRootURL,
            objectAcceptanceReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3WebKitObjectAcceptanceReportWriter.reportFileName
                ),
            contextReadinessReportURL: contextReportURL,
            runtimeBridgePrerequisitesReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeBridgePrerequisitesReportWriter
                        .reportFileName
                ),
            runtimeMessagingContractReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeMessagingContractReportWriter
                        .reportFileName
                ),
            runtimeListenerContractReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeListenerContractReportWriter
                        .reportFileName
                ),
            runtimeBridgeReadinessReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeBridgeReadinessReportWriter
                        .reportFileName
                ),
            runtimeLoadabilityReport: runtimeReport,
            candidate: candidate,
            objectAcceptanceReport: objectReport,
            contextReadinessReport: contextReport,
            runtimeBridgePrerequisitesReport:
                runtimeBridgePrerequisitesReport,
            runtimeMessagingContractReport:
                runtimeMessagingContractReport,
            runtimeListenerContractReport:
                runtimeListenerContractReport,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            consumerDiagnostic: consumer
        )
    }

    @MainActor
    @available(macOS 15.5, *)
    func makeEmptyControllerOwner() throws -> ChromeMV3EmptyControllerOwner {
        let profileIdentifier = fixedControllerIdentifier.uuidString
        let decision = ChromeMV3ControllerCreationGate.evaluate(
            input: ChromeMV3ControllerCreationGateInput(
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileHostControllerState: .absentNotCreated,
                explicitControllerCreationAllowed: true,
                requestedContextLoading: false,
                requestedNormalTabAttachment: false,
                profileIdentifier: profileIdentifier,
                profileDataStoreIdentity:
                    .profileIdentifier(profileIdentifier),
                disabledRuntimeInvariantStatus: .satisfied
            )
        )
        return try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: decision,
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: fixedControllerIdentifier
            )
        )
    }

    private func writeSourceFixture(candidateRootURL: URL) throws -> URL {
        let sourceRootURL = candidateRootURL
            .appendingPathComponent("source-mv3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRootURL,
            withIntermediateDirectories: true
        )
        try writeJSONObject(
            serviceWorkerManifest(),
            to: sourceRootURL.appendingPathComponent("manifest.json")
        )
        try """
        chrome.runtime.onInstalled.addListener(() => {});

        """.write(
            to: sourceRootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        try """
        chrome.runtime.sendMessage({ type: "readiness-pipeline-probe" });

        """.write(
            to: sourceRootURL.appendingPathComponent("content.js"),
            atomically: true,
            encoding: .utf8
        )
        try """
        <!doctype html>
        <html><head></head><body>Readiness pipeline</body></html>

        """.write(
            to: sourceRootURL.appendingPathComponent("popup.html"),
            atomically: true,
            encoding: .utf8
        )
        return sourceRootURL
    }

    private func objectProbeGateInput(
        candidate: ChromeMV3RewrittenVariantCandidate,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport,
        extensionsModuleEnabled: Bool
    ) -> ChromeMV3ExtensionObjectProbeGateInput {
        ChromeMV3ExtensionObjectProbeGateInput(
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostModuleState: .enabled,
            explicitInternalExtensionObjectProbeAllowed: true,
            resourceBaseURLPath: candidate.rewrittenVariantRootPath,
            generatedBundleID: candidate.id,
            generatedBundleHash: candidate.rewrittenManifestSHA256,
            generatedRewrittenBundleExists: candidate.rewrittenVariantExists,
            runtimeLoadabilityReportExists: true,
            runtimeLoadabilityReportID: runtimeReport.id,
            runtimeLoadabilityReportPath:
                candidate.runtimeLoadabilityReportPath,
            runtimeLoadabilityReportSHA256:
                candidate.runtimeLoadabilityReportSHA256,
            manifestVersion: candidate.manifestVersion,
            runtimeLoadable: runtimeReport.runtimeLoadable,
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

    @MainActor
    private func objectProbeDiagnostics(
        mode: ChromeMV3ReadinessFixtureObjectProbeMode,
        decision: ChromeMV3ExtensionObjectProbeGateDecision
    ) async throws -> ChromeMV3ExtensionObjectProbeDiagnostics {
        switch mode {
        case .actual:
            let owner = ChromeMV3ExtensionObjectProbeOwner(
                gateDecision: decision
            )
            let diagnostics = await owner.runProbeIfAllowed()
            owner.tearDown()
            return diagnostics
        case .syntheticFailure:
            return .failed(
                gateDecision: decision,
                error: ChromeMV3ExtensionObjectProbeErrorDiagnostic(
                    nsError: NSError(
                        domain: "SumiTests.ChromeMV3ReadinessFixturePipeline",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Synthetic object-acceptance failure.",
                        ]
                    )
                )
            )
        }
    }

    private func serviceWorkerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Readiness Pipeline MV3",
            "version": "1.0.0",
            "permissions": ["nativeMessaging", "storage"],
            "host_permissions": ["https://example.com/*"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "all_frames": true,
                    "match_about_blank": true,
                ],
            ],
            "action": [
                "default_popup": "popup.html",
            ],
        ]
    }

    private func writeJSONObject(
        _ object: [String: Any],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
