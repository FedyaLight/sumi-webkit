import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ContextReadinessReportTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleDoesNotGenerateContextReadinessReport()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context-readiness module diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-disabled-module",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ChromeMV3ContextReadinessModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let report = module.chromeMV3ContextReadinessReportIfEnabled(
            explicitControllerCreationAllowed: true,
            candidate: candidate,
            runtimeLoadabilityReport: nil,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        ChromeMV3ContextReadinessReportWriter.reportFileName
                    )
                    .path
            )
        )
    }

    func testMissingObjectAcceptanceReportBlocksFutureContextEligibility()
        throws
    {
        let root = try makeSimpleRewrittenRoot(
            named: "context-missing-object-report",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            loadingObjectAcceptanceReportFrom: root,
            emptyControllerDiagnostics: nil,
            runtimeLoadabilityReport: nil
        )

        XCTAssertFalse(report.futureContextEligible)
        XCTAssertTrue(
            report.blockers.contains(.objectAcceptanceReportMissing)
        )
        XCTAssertEqual(report.objectProbeStatus, .reportMissing)
        XCTAssertFalse(report.objectAcceptedByWebKit)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(report.nextRequiredPromptCategory, .fixObjectAcceptance)
    }

    @MainActor
    func testObjectRejectedByWebKitBlocksFutureContextEligibility()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-object-rejected",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)
        let objectReport = makeObjectAcceptanceReport(
            rootURL: root,
            accepted: false
        )

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: objectReport,
            emptyControllerDiagnostics: try makeCreatedEmptyControllerDiagnostics(),
            runtimeLoadabilityReport: nil
        )

        XCTAssertFalse(report.futureContextEligible)
        XCTAssertFalse(report.objectAcceptedByWebKit)
        XCTAssertTrue(report.blockers.contains(.webKitObjectNotAccepted))
        XCTAssertEqual(report.nextRequiredPromptCategory, .fixObjectAcceptance)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testObjectAcceptedButMissingEmptyControllerBlocksFutureEligibility()
        throws
    {
        let root = try makeSimpleRewrittenRoot(
            named: "context-missing-empty-controller",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: makeObjectAcceptanceReport(
                rootURL: root,
                accepted: true
            ),
            emptyControllerDiagnostics: nil,
            runtimeLoadabilityReport: nil
        )

        XCTAssertTrue(report.objectAcceptedByWebKit)
        XCTAssertFalse(report.futureContextEligible)
        XCTAssertTrue(
            report.blockers.contains(.emptyControllerDiagnosticsMissing)
        )
        XCTAssertEqual(report.emptyControllerState.status, .missing)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testAcceptedObjectEmptyControllerAndMatchingDataStoreCanBeFutureEligible()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-ready",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: makeObjectAcceptanceReport(
                rootURL: root,
                accepted: true
            ),
            emptyControllerDiagnostics: try makeCreatedEmptyControllerDiagnostics(),
            runtimeLoadabilityReport: nil
        )

        XCTAssertTrue(report.objectAcceptedByWebKit)
        XCTAssertTrue(report.objectAcceptanceBlockersResolved)
        XCTAssertEqual(report.emptyControllerState.status, .available)
        XCTAssertEqual(
            report.controllerDataStoreIdentityStatus.status,
            .matched
        )
        XCTAssertEqual(
            report.sameControllerFutureRequirementStatus.status,
            .available
        )
        XCTAssertTrue(report.futureContextEligible)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(report.nextRequiredPromptCategory, .addContextCreationGate)
    }

    @MainActor
    func testStaleAttachedWebViewsBlockByDefault() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Live attachment diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-stale-webviews",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)
        let staleSnapshot = ChromeMV3LiveNormalTabAttachmentRecorderSnapshot(
            recentDecisions: [],
            attachedConfigurationCount: 1,
            createdAttachedWebViewCount: 0,
            staleOrNeedsRecreationCount: 1,
            attachedTabDiagnosticIdentifiers: [],
            staleOrNeedsRecreationTabDiagnosticIdentifiers: [
                "tab-stale-1",
            ],
            accidentallyAttachedAuxiliarySurface: false,
            auxiliaryAttachmentSequenceNumbers: [],
            runtimeLoadable: false,
            canLoadContextNow: false,
            contextCount: 0,
            contextLoadCalled: false,
            webExtensionCreated: false,
            webExtensionContextCreated: false,
            generatedExtensionBundleLoaded: false,
            nativeMessagingLaunched: false,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false
        )

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: makeObjectAcceptanceReport(
                rootURL: root,
                accepted: true
            ),
            emptyControllerDiagnostics: try makeCreatedEmptyControllerDiagnostics(),
            liveNormalTabAttachmentSnapshot: staleSnapshot,
            runtimeLoadabilityReport: nil
        )

        XCTAssertFalse(report.futureContextEligible)
        XCTAssertTrue(
            report.blockers.contains(.staleAttachedWebViewsPresent)
        )
        XCTAssertEqual(report.staleNeedsRecreationStatus.policy, .blocker)
        XCTAssertTrue(
            report.staleNeedsRecreationStatus
                .blocksFutureContextEligibility
        )
        XCTAssertEqual(
            report.nextRequiredPromptCategory,
            .resolveStaleWebViews
        )
    }

    @MainActor
    func testUnsupportedAndDeferredAPIsRemainRuntimeBlockers()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-runtime-blockers",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)
        let runtimeReport = makeRuntimeLoadabilityReport(
            rootPath: root.path,
            unsupportedAPIs: [.debugger],
            deferredAPIs: [.nativeMessaging],
            blockers: [
                "Native messaging host bridge is not implemented.",
            ]
        )

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: makeObjectAcceptanceReport(
                rootURL: root,
                accepted: true
            ),
            emptyControllerDiagnostics: try makeCreatedEmptyControllerDiagnostics(),
            runtimeLoadabilityReport: runtimeReport
        )

        XCTAssertTrue(report.runtimeBlockers.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(
            report.runtimeBlockers.deferredAPIs.contains(.nativeMessaging)
        )
        XCTAssertTrue(
            report.runtimeBlockers
                .unsupportedDeferredAPIsRemainRuntimeBlockers
        )
        XCTAssertEqual(
            report.nextRequiredPromptCategory,
            .blockedByUnsupportedAPIs
        )
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testPasswordManagerLikeFixtureReportsRuntimePermissionAndNativeBlockers()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-password-manager",
            manifest: passwordManagerManifest(),
            files: [
                "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
                "content.js": "chrome.runtime.sendMessage({type: 'probe'});\n",
                "popup.html": "<!doctype html><title>Popup</title>",
            ]
        )
        let candidate = makeCandidate(rootURL: root)
        let runtimeReport = makePasswordManagerRuntimeLoadabilityReport(
            rootPath: root.path
        )

        let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: makeObjectAcceptanceReport(
                rootURL: root,
                accepted: true,
                runtimeReport: runtimeReport
            ),
            emptyControllerDiagnostics: try makeCreatedEmptyControllerDiagnostics(),
            runtimeLoadabilityReport: runtimeReport
        )

        let password = report.passwordManagerReadiness
        XCTAssertTrue(password.objectAcceptedByWebKit)
        XCTAssertTrue(password.contentScriptsPresent)
        XCTAssertTrue(password.actionPopupPresent)
        XCTAssertTrue(password.hostPermissionsPresent)
        XCTAssertTrue(password.storagePermissionPresent)
        XCTAssertTrue(password.nativeMessagingPermissionPresent)
        XCTAssertFalse(password.nativeMessagingBridgeImplemented)
        XCTAssertFalse(password.runtimeMessagingBridgeImplemented)
        XCTAssertFalse(password.permissionBrokerActiveTabImplemented)
        XCTAssertFalse(password.controlledInputPageWorldBehaviorVerified)
        XCTAssertFalse(password.serviceWorkerLifecycleVerified)
        XCTAssertFalse(password.futureContextCreated)
        XCTAssertFalse(password.runtimeLoadable)
        XCTAssertTrue(
            report.runtimeBlockers.nativeMessagingBlockers.contains {
                $0.localizedCaseInsensitiveContains("native")
            }
        )
        XCTAssertTrue(
            report.runtimeBlockers.runtimeMessagingBlockers.contains {
                $0.localizedCaseInsensitiveContains("runtime messaging")
            }
        )
        XCTAssertTrue(
            report.runtimeBlockers.permissionActiveTabBlockers.contains {
                $0.localizedCaseInsensitiveContains("activeTab")
            }
        )
        XCTAssertEqual(
            report.nextRequiredPromptCategory,
            .addRuntimeBridgePrerequisites
        )
    }

    @MainActor
    func testReportWriterIsDeterministicAndConsumesObjectAcceptanceFile()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-writer",
            manifest: minimalManifest(),
            files: [:]
        )
        let candidate = makeCandidate(rootURL: root)
        let objectReport = makeObjectAcceptanceReport(
            rootURL: root,
            accepted: true
        )
        try ChromeMV3WebKitObjectAcceptanceReportWriter.write(
            objectReport,
            toRewrittenBundleRoot: root
        )
        let emptyControllerDiagnostics = try makeCreatedEmptyControllerDiagnostics()

        let first = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            loadingObjectAcceptanceReportFrom: root,
            emptyControllerDiagnostics: emptyControllerDiagnostics,
            runtimeLoadabilityReport: nil
        )
        try ChromeMV3ContextReadinessReportWriter.write(
            first,
            toRewrittenBundleRoot: root
        )
        let firstData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContextReadinessReportWriter.reportFileName
            )
        )
        let second = ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            loadingObjectAcceptanceReportFrom: root,
            emptyControllerDiagnostics: emptyControllerDiagnostics,
            runtimeLoadabilityReport: nil
        )
        try ChromeMV3ContextReadinessReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContextReadinessReportWriter.reportFileName
            )
        )

        XCTAssertEqual(first.webKitObjectAcceptanceReportHash?.count, 64)
        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertTrue(first.futureContextEligible)
    }

    func testReportConsumerBlocksMissingGeneratedContextReadinessReport()
        throws
    {
        let root = try makeTemporaryDirectory()
        let diagnostic =
            ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromRewrittenBundleRoot: root
            )

        XCTAssertEqual(diagnostic.state, .missingReport)
        XCTAssertFalse(diagnostic.canImplementRecommendedBranch)
        XCTAssertNil(diagnostic.nextRequiredPromptCategory)
        XCTAssertNil(diagnostic.rawNextRequiredPromptCategory)
        XCTAssertEqual(
            diagnostic.reportFileName,
            ChromeMV3ContextReadinessReportWriter.reportFileName
        )
        XCTAssertEqual(
            diagnostic.allowedNextRequiredPromptCategories,
            ChromeMV3ContextReadinessNextPromptCategory.allCases
                .map(\.rawValue)
        )
        XCTAssertTrue(
            diagnostic.blockingReasons.contains {
                $0.contains(
                    "Missing generated Chrome MV3 context-readiness report"
                )
                    && $0.contains(
                        ChromeMV3ContextReadinessReportWriter.reportFileName
                    )
            }
        )
        XCTAssertTrue(
            diagnostic.requiredActions.contains {
                $0.contains("Generate")
                    && $0.contains(
                        ChromeMV3ContextReadinessReportWriter.reportFileName
                    )
            }
        )
    }

    func testReportConsumerBlocksCorruptContextReadinessReport()
        throws
    {
        let reportURL = try makeContextReadinessReportURL()
        try Data("{".utf8).write(to: reportURL)

        let diagnostic =
            ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromReportURL: reportURL
            )

        XCTAssertEqual(diagnostic.state, .corruptReport)
        XCTAssertFalse(diagnostic.canImplementRecommendedBranch)
        XCTAssertNil(diagnostic.nextRequiredPromptCategory)
        XCTAssertTrue(
            diagnostic.blockingReasons.contains {
                $0.contains("not valid JSON")
            }
        )
    }

    func testReportConsumerBlocksMissingNextRequiredPromptCategory()
        throws
    {
        let reportURL = try makeContextReadinessReportURL()
        try writeJSONObject(["schemaVersion": 1], to: reportURL)

        let diagnostic =
            ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromReportURL: reportURL
            )

        XCTAssertEqual(
            diagnostic.state,
            .missingNextRequiredPromptCategory
        )
        XCTAssertFalse(diagnostic.canImplementRecommendedBranch)
        XCTAssertNil(diagnostic.nextRequiredPromptCategory)
        XCTAssertTrue(
            diagnostic.blockingReasons.contains {
                $0.contains("missing nextRequiredPromptCategory")
            }
        )
    }

    func testReportConsumerBlocksUnsupportedNextRequiredPromptCategory()
        throws
    {
        let reportURL = try makeContextReadinessReportURL()
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "nextRequiredPromptCategory": "createContextNow",
            ],
            to: reportURL
        )

        let diagnostic =
            ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromReportURL: reportURL
            )

        XCTAssertEqual(
            diagnostic.state,
            .unsupportedNextRequiredPromptCategory
        )
        XCTAssertFalse(diagnostic.canImplementRecommendedBranch)
        XCTAssertNil(diagnostic.nextRequiredPromptCategory)
        XCTAssertEqual(
            diagnostic.rawNextRequiredPromptCategory,
            "createContextNow"
        )
        XCTAssertTrue(
            diagnostic.blockingReasons.contains {
                $0.contains("Unsupported Chrome MV3 nextRequiredPromptCategory")
            }
        )
    }

    func testReportConsumerReadsAllowedNextRequiredPromptCategory()
        throws
    {
        let reportURL = try makeContextReadinessReportURL()
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "nextRequiredPromptCategory":
                    ChromeMV3ContextReadinessNextPromptCategory
                    .fixObjectAcceptance.rawValue,
            ],
            to: reportURL
        )

        let diagnostic =
            ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromReportURL: reportURL
            )

        XCTAssertEqual(diagnostic.state, .ready)
        XCTAssertTrue(diagnostic.canImplementRecommendedBranch)
        XCTAssertEqual(
            diagnostic.nextRequiredPromptCategory,
            .fixObjectAcceptance
        )
        XCTAssertEqual(
            diagnostic.rawNextRequiredPromptCategory,
            ChromeMV3ContextReadinessNextPromptCategory
                .fixObjectAcceptance.rawValue
        )
        XCTAssertTrue(diagnostic.blockingReasons.isEmpty)
    }

    func testSourceGuardsKeepContextReadinessPreflightNonRuntime()
        throws
    {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let creationFiles = sourceFiles
            .filter { $0.contents.contains("WK" + "WebExtension(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            creationFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let chromeMV3Source = sourceFiles
            .map(\.contents)
            .joined(separator: "\n")
        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(chromeMV3Source.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                chromeMV3Source.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private func makeContextReadinessReportURL() throws -> URL {
        try makeTemporaryDirectory()
            .appendingPathComponent(
                ChromeMV3ContextReadinessReportWriter.reportFileName
            )
    }

    private func writeJSONObject(
        _ object: [String: Any],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
    }

    private func makeObjectAcceptanceReport(
        rootURL: URL,
        accepted: Bool,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport? = nil
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
                        domain: "SumiTests.ContextReadiness",
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
        runtimeReport: ChromeMV3RuntimeLoadabilityReport?
    ) -> ChromeMV3ExtensionObjectProbeGateInput {
        ChromeMV3ExtensionObjectProbeGateInput(
            extensionsModuleEnabled: true,
            profileHostModuleState: .enabled,
            explicitInternalExtensionObjectProbeAllowed: true,
            resourceBaseURLPath: rootURL.path,
            generatedBundleID: candidate.id,
            generatedBundleHash:
                candidate.rewrittenManifestSHA256
                    ?? runtimeReport?.rewrittenManifestHash?.sha256,
            generatedRewrittenBundleExists: true,
            runtimeLoadabilityReportExists: true,
            runtimeLoadabilityReportID:
                runtimeReport?.id ?? "runtime-loadability-test",
            runtimeLoadabilityReportPath:
                candidate.runtimeLoadabilityReportPath,
            runtimeLoadabilityReportSHA256:
                candidate.runtimeLoadabilityReportSHA256,
            manifestVersion: 3,
            runtimeLoadable: false,
            staticRuntimeBlockers: runtimeReport?.blockers ?? [],
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
    private func makeCreatedEmptyControllerDiagnostics()
        throws -> ChromeMV3EmptyControllerDiagnostics
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let profileIdentifier = UUID().uuidString
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
        let owner = try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: decision,
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier:
                    try XCTUnwrap(UUID(uuidString: profileIdentifier))
            )
        )
        return owner.diagnostics()
    }

    private func makeRuntimeLoadabilityReport(
        rootPath: String,
        unsupportedAPIs: [ChromeMV3API] = [],
        deferredAPIs: [ChromeMV3API] = [],
        blockers: [String] = [],
        passwordReadiness:
            ChromeMV3PasswordManagerRuntimeReadinessReport? = nil
    ) -> ChromeMV3RuntimeLoadabilityReport {
        ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-test",
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
            failedChecks: unsupportedAPIs.isEmpty ? [] : [.unsupportedAPIs],
            deferredChecks: deferredAPIs.isEmpty ? [] : [.deferredAPIs],
            warnings: [],
            missing: [],
            blockers: blockers,
            unsupportedAPIs: unsupportedAPIs,
            deferredAPIs: deferredAPIs,
            requiredFutureRuntimeComponents: [],
            passwordManagerReadiness: passwordReadiness
                ?? ChromeMV3PasswordManagerRuntimeReadinessReport(
                    contentScriptsPresent: false,
                    allFramesDetected: false,
                    matchAboutBlankDetected: false,
                    hostPermissionsPresent: false,
                    actionPopupPresent: false,
                    storagePermissionPresent: false,
                    nativeMessagingDetected: false,
                    nativeMessagingBlocked: false,
                    runtimeMessagingImplemented: false,
                    controlledInputPageWorldBehaviorVerified: false,
                    serviceWorkerLifecycleVerified: false,
                    blockers: [],
                    deferredChecks: []
                ),
            structurallyValid: unsupportedAPIs.isEmpty,
            runtimeLoadable: false,
            runtimeLoadableFalseReason: "Context-readiness test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makePasswordManagerRuntimeLoadabilityReport(
        rootPath: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        makeRuntimeLoadabilityReport(
            rootPath: rootPath,
            unsupportedAPIs: [],
            deferredAPIs: [.nativeMessaging],
            blockers: [
                "Native messaging host bridge is not implemented.",
                "Runtime messaging is not implemented.",
            ],
            passwordReadiness:
                ChromeMV3PasswordManagerRuntimeReadinessReport(
                    contentScriptsPresent: true,
                    allFramesDetected: true,
                    matchAboutBlankDetected: true,
                    hostPermissionsPresent: true,
                    actionPopupPresent: true,
                    storagePermissionPresent: true,
                    nativeMessagingDetected: true,
                    nativeMessagingBlocked: true,
                    runtimeMessagingImplemented: false,
                    controlledInputPageWorldBehaviorVerified: false,
                    serviceWorkerLifecycleVerified: false,
                    blockers: [
                        "Native messaging is detected but blocked/deferred.",
                        "Runtime messaging bridge is not implemented yet.",
                        "Controlled-input and page-world behavior is not verified yet.",
                        "Service-worker lifecycle is not verified yet.",
                    ],
                    deferredChecks: [
                        "Password-manager fixture readiness is a report only; Sumi does not claim password-manager support.",
                    ]
                )
        )
    }

    private func minimalManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": "1.0.0",
        ]
    }

    private func passwordManagerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Password Manager",
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
        id: String = "context-readiness-candidate"
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
        probe: ChromeMV3ContextReadinessModuleProbe
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
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
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
private final class ChromeMV3ContextReadinessModuleProbe {
    let profile = Profile(name: "Chrome MV3 Context Readiness Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
