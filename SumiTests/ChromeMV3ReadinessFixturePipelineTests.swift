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
            .map(\.contents)
            .joined(separator: "\n")
        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
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
    var runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    var candidate: ChromeMV3RewrittenVariantCandidate?
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    var contextReadinessReport: ChromeMV3ContextReadinessReport?
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
                runtimeLoadabilityReport: nil,
                candidate: nil,
                objectAcceptanceReport: nil,
                contextReadinessReport: nil,
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
        let consumer = ChromeMV3ContextReadinessReportConsumer.diagnostic(
            fromRewrittenBundleRoot: variant.variantRootURL
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
            contextReadinessReportURL: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3ContextReadinessReportWriter.reportFileName
                ),
            runtimeLoadabilityReport: runtimeReport,
            candidate: candidate,
            objectAcceptanceReport: objectReport,
            contextReadinessReport: contextReport,
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
