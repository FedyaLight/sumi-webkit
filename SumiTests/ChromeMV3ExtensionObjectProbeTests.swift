import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ExtensionObjectProbeTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testGateBlocksDisabledModuleAndKeepsContextLoadingFalse() {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                extensionsModuleEnabled: false,
                profileHostModuleState: .disabled
            )
        )

        XCTAssertFalse(decision.canCreateExtensionObjectNow)
        XCTAssertFalse(decision.canCreateContextNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertTrue(decision.blockers.contains(.extensionsModuleDisabled))
        XCTAssertTrue(decision.blockers.contains(.profileHostDisabled))
    }

    func testGateRequiresExplicitInternalProbeFlag() {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                explicitInternalExtensionObjectProbeAllowed: false
            )
        )

        XCTAssertFalse(decision.canCreateExtensionObjectNow)
        XCTAssertTrue(decision.blockers.contains(.explicitObjectProbeNotAllowed))
        XCTAssertFalse(decision.canCreateContextNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    func testGateBlocksMissingGeneratedRewrittenBundle() {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(generatedRewrittenBundleExists: false)
        )

        XCTAssertFalse(decision.canCreateExtensionObjectNow)
        XCTAssertTrue(decision.blockers.contains(.generatedRewrittenBundleMissing))
    }

    func testGateBlocksMissingRuntimeLoadabilityReport() {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                runtimeLoadabilityReportExists: false,
                runtimeLoadable: nil
            )
        )

        XCTAssertFalse(decision.canCreateExtensionObjectNow)
        XCTAssertTrue(decision.blockers.contains(.runtimeLoadabilityReportMissing))
        XCTAssertTrue(decision.blockers.contains(.runtimeLoadableMissingOrTrue))
    }

    func testGateAllowsObjectProbeWhileContextAndLoadingRemainBlocked() {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                staticRuntimeBlockers: [
                    "WebKit runtime loading is not yet wired.",
                ],
                staleAttachedWebViewCount: 1
            )
        )

        XCTAssertTrue(decision.canCreateExtensionObjectNow)
        XCTAssertFalse(decision.canCreateContextNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertTrue(
            decision.warnings.contains {
                $0.contains("stale")
            }
        )
        XCTAssertTrue(
            decision.warnings.contains {
                $0.contains("must not create or load a context")
            }
        )
    }

    func testGateRejectsContextLoadingControllerLoadingRuntimeAndNativeRequests() {
        let disallowedRuntimeFlag = !false
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                runtimeLoadable: disallowedRuntimeFlag,
                requestedContextCreation: true,
                requestedContextLoading: true,
                requestedControllerLoad: true,
                requestedExtensionCodeExecution: true,
                requestedUserScriptRegistration: true,
                requestedNativeMessagingLaunch: true
            )
        )

        XCTAssertFalse(decision.canCreateExtensionObjectNow)
        XCTAssertTrue(decision.blockers.contains(.runtimeLoadableMissingOrTrue))
        XCTAssertTrue(decision.blockers.contains(.contextCreationRequested))
        XCTAssertTrue(decision.blockers.contains(.contextLoadingRequested))
        XCTAssertTrue(decision.blockers.contains(.controllerLoadRequested))
        XCTAssertTrue(decision.blockers.contains(.extensionCodeExecutionRequested))
        XCTAssertTrue(decision.blockers.contains(.userScriptRegistrationRequested))
        XCTAssertTrue(decision.blockers.contains(.nativeMessagingLaunchRequested))
        XCTAssertFalse(decision.canCreateContextNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    @MainActor
    func testDisabledModuleReturnsNilAndCreatesNoProbeOwnerOrRuntime() async throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let fixture = try makeGeneratedRewrittenFixture(
            named: "object-probe-disabled"
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ChromeMV3ExtensionObjectModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let diagnostics =
            module.chromeMV3ExtensionObjectProbeDiagnosticsIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: true,
                candidate: fixture.candidate,
                runtimeLoadabilityReport: fixture.report
            )
        let acceptanceReport =
            module.chromeMV3WebKitObjectAcceptanceReportIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: true,
                candidate: fixture.candidate,
                runtimeLoadabilityReport: fixture.report,
                writeReport: true
            )
        let result = await module.runChromeMV3ExtensionObjectProbeIfEnabled(
            explicitInternalExtensionObjectProbeAllowed: true,
            candidate: fixture.candidate,
            runtimeLoadabilityReport: fixture.report
        )

        XCTAssertNil(diagnostics)
        XCTAssertNil(acceptanceReport)
        XCTAssertNil(result)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.variantRootURL
                    .appendingPathComponent(
                        ChromeMV3WebKitObjectAcceptanceReportWriter
                            .reportFileName
                    )
                    .path
            )
        )
    }

    @MainActor
    func testEnabledModuleWithoutExplicitFlagBlocksProbeAndCreatesNoOwner()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let fixture = try makeGeneratedRewrittenFixture(
            named: "object-probe-explicit-off"
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ChromeMV3ExtensionObjectModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let diagnostics = try XCTUnwrap(
            module.chromeMV3ExtensionObjectProbeDiagnosticsIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: false,
                candidate: fixture.candidate,
                runtimeLoadabilityReport: fixture.report
            )
        )
        let resultOptional = await module
            .runChromeMV3ExtensionObjectProbeIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: false,
                candidate: fixture.candidate,
                runtimeLoadabilityReport: fixture.report
        )
        let result = try XCTUnwrap(resultOptional)

        XCTAssertEqual(diagnostics.state, .blocked)
        XCTAssertEqual(result.state, .blocked)
        XCTAssertTrue(
            result.gateDecision.blockers.contains(
                .explicitObjectProbeNotAllowed
            )
        )
        XCTAssertFalse(result.extensionObjectCreated)
        XCTAssertEqual(result.contextCount, 0)
        XCTAssertEqual(result.controllerLoadCount, 0)
        XCTAssertFalse(result.generatedBundleLoadedIntoController)
        XCTAssertFalse(result.runtimeLoadable)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testGeneratedRewrittenFixtureAttemptsWKWebExtensionObjectCreation()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let fixture = try makeGeneratedRewrittenFixture(
            named: "object-probe-generated"
        )
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                resourceBaseURLPath: fixture.variantRootURL.path,
                generatedBundleID: fixture.candidate.id,
                generatedBundleHash:
                    fixture.candidate.rewrittenManifestSHA256,
                runtimeLoadabilityReportID: fixture.report.id,
                runtimeLoadabilityReportPath:
                    fixture.candidate.runtimeLoadabilityReportPath,
                runtimeLoadabilityReportSHA256:
                    fixture.candidate.runtimeLoadabilityReportSHA256,
                staticRuntimeBlockers: fixture.report.blockers
            )
        )
        let owner = ChromeMV3ExtensionObjectProbeOwner(
            gateDecision: decision
        )

        let diagnostics = await owner.runProbeIfAllowed()

        XCTAssertTrue(decision.canCreateExtensionObjectNow)
        XCTAssertTrue(diagnostics.attempted)
        XCTAssertTrue([.created, .failed].contains(diagnostics.state))
        XCTAssertEqual(diagnostics.resourceBaseURLPath, fixture.variantRootURL.path)
        XCTAssertEqual(diagnostics.generatedBundleID, fixture.candidate.id)
        XCTAssertEqual(
            diagnostics.generatedBundleHash,
            fixture.candidate.rewrittenManifestSHA256
        )
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.controllerLoadCount, 0)
        XCTAssertFalse(diagnostics.generatedBundleLoadedIntoController)
        XCTAssertFalse(diagnostics.canCreateContextNow)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertFalse(diagnostics.extensionCodeExecuted)
        XCTAssertEqual(diagnostics.userScriptRegistrationCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)

        switch diagnostics.state {
        case .created:
            XCTAssertTrue(diagnostics.extensionObjectCreated)
            XCTAssertNil(diagnostics.error)
            XCTAssertTrue(owner.webExtensionObjectCreated)
        case .failed:
            XCTAssertFalse(diagnostics.extensionObjectCreated)
            XCTAssertNotNil(diagnostics.error)
            XCTAssertFalse(owner.webExtensionObjectCreated)
        default:
            XCTFail("Expected created or failed object probe state.")
        }

        let report = ChromeMV3WebKitObjectAcceptanceReportGenerator
            .makeReport(
                candidate: fixture.candidate,
                gateDecision: decision,
                probeDiagnostics: diagnostics,
                runtimeLoadabilityReport: fixture.report
            )
        XCTAssertTrue(report.probeAttempted)
        XCTAssertEqual(report.objectAcceptedByWebKit, diagnostics.extensionObjectCreated)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        if diagnostics.extensionObjectCreated {
            XCTAssertTrue(report.classificationCategories.contains(.objectCreated))
        } else {
            XCTAssertTrue(
                report.classificationFindings.contains {
                    $0.severity == .objectBlocking
                        || $0.category == .unknownWebKitError
                }
            )
        }
    }

    @MainActor
    func testInvalidBundleFailureRecordsErrorWithoutContextOrControllerLoad()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let invalidRoot = try makeTemporaryDirectory()
            .appendingPathComponent("invalid-generated-rewritten", isDirectory: true)
        try FileManager.default.createDirectory(
            at: invalidRoot,
            withIntermediateDirectories: true
        )
        let report = makeRuntimeLoadabilityReport(
            rootPath: invalidRoot.path,
            id: "invalid-runtime-report"
        )
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                resourceBaseURLPath: invalidRoot.path,
                generatedBundleID: "invalid-generated",
                generatedBundleHash: String(repeating: "1", count: 64),
                runtimeLoadabilityReportID: report.id,
                runtimeLoadabilityReportPath: nil,
                runtimeLoadabilityReportSHA256: nil,
                staticRuntimeBlockers: report.blockers
            )
        )
        let owner = ChromeMV3ExtensionObjectProbeOwner(
            gateDecision: decision
        )

        let diagnostics = await owner.runProbeIfAllowed()

        XCTAssertTrue(decision.canCreateExtensionObjectNow)
        XCTAssertEqual(diagnostics.state, .failed)
        XCTAssertTrue(diagnostics.attempted)
        XCTAssertFalse(diagnostics.extensionObjectCreated)
        XCTAssertNotNil(diagnostics.error)
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.controllerLoadCount, 0)
        XCTAssertFalse(diagnostics.generatedBundleLoadedIntoController)
        XCTAssertFalse(diagnostics.runtimeLoadable)
    }

    func testObjectAcceptanceReportClassifiesMissingGeneratedBundle() throws {
        let root = try makeTemporaryDirectory()
            .appendingPathComponent("missing-generated-rewritten", isDirectory: true)
        let candidate = makeCandidate(rootURL: root)
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                resourceBaseURLPath: root.path,
                generatedRewrittenBundleExists: false,
                staticRuntimeBlockers: ["WebKit runtime loading is not yet wired."]
            )
        )

        let report = ChromeMV3WebKitObjectAcceptanceReportGenerator
            .makeReport(
                candidate: candidate,
                gateDecision: decision,
                probeDiagnostics: nil,
                runtimeLoadabilityReport: nil
            )

        XCTAssertFalse(report.probeAttempted)
        XCTAssertTrue(report.classificationCategories.contains(.blockedByGate))
        XCTAssertTrue(report.classificationCategories.contains(.missingGeneratedBundle))
        XCTAssertTrue(report.objectAcceptanceLikelyFixableByGenerator)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testObjectAcceptanceReportClassifiesMissingManifest() throws {
        let root = try makeTemporaryDirectory()
            .appendingPathComponent("missing-manifest", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let candidate = makeCandidate(rootURL: root)
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(resourceBaseURLPath: root.path)
        )

        let report = ChromeMV3WebKitObjectAcceptanceReportGenerator
            .makeReport(
                candidate: candidate,
                gateDecision: decision,
                probeDiagnostics: nil,
                runtimeLoadabilityReport: nil
            )

        XCTAssertTrue(report.classificationCategories.contains(.missingManifest))
        XCTAssertTrue(report.staticInspection.missingResourcePaths.isEmpty)
        XCTAssertTrue(report.objectAcceptanceLikelyFixableByGenerator)
        XCTAssertFalse(report.objectAcceptedByWebKit)
    }

    func testObjectAcceptanceReportClassifiesInvalidManifestJSON() throws {
        let root = try makeTemporaryDirectory()
            .appendingPathComponent("invalid-manifest", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try "{".write(
            to: root.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        let candidate = makeCandidate(rootURL: root)
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(resourceBaseURLPath: root.path)
        )

        let report = ChromeMV3WebKitObjectAcceptanceReportGenerator
            .makeReport(
                candidate: candidate,
                gateDecision: decision,
                probeDiagnostics: nil,
                runtimeLoadabilityReport: nil
            )

        XCTAssertTrue(report.classificationCategories.contains(.manifestJSONInvalid))
        XCTAssertFalse(report.staticInspection.manifestJSONValid)
        XCTAssertTrue(report.objectAcceptanceLikelyFixableByGenerator)
    }

    func testObjectAcceptanceReportClassifiesMissingWrapperPath() throws {
        let root = try makeSimpleRewrittenRoot(
            named: "missing-wrapper",
            manifest: [
                "manifest_version": 3,
                "name": "Missing Wrapper",
                "version": "1.0.0",
                "background": [
                    "service_worker": "_sumi_runtime/service-worker-wrapper.classic.js",
                ],
            ],
            files: [:]
        )
        let report = reportForStaticRoot(root)

        XCTAssertTrue(
            report.classificationCategories.contains(.serviceWorkerWrapperRejected)
        )
        XCTAssertTrue(report.objectAcceptanceLikelyFixableByGenerator)
        XCTAssertTrue(
            report.staticInspection.missingResourcePaths.contains(
                "_sumi_runtime/service-worker-wrapper.classic.js"
            )
        )
    }

    func testObjectAcceptanceReportClassifiesMissingContentScriptResource()
        throws
    {
        let root = try makeSimpleRewrittenRoot(
            named: "missing-content-script",
            manifest: [
                "manifest_version": 3,
                "name": "Missing Content Script",
                "version": "1.0.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["missing-content.js"],
                    ],
                ],
            ],
            files: [:]
        )
        let report = reportForStaticRoot(root)

        XCTAssertTrue(
            report.classificationCategories.contains(.contentScriptResourceRejected)
        )
        XCTAssertTrue(
            report.staticInspection.missingResourcePaths.contains(
                "missing-content.js"
            )
        )
        XCTAssertTrue(report.objectAcceptanceLikelyFixableByGenerator)
    }

    func testUnsupportedDeferredAPIsRemainRuntimeContextBlockers()
        throws
    {
        let root = try makeSimpleRewrittenRoot(
            named: "deferred-api-manifest",
            manifest: [
                "manifest_version": 3,
                "name": "Deferred APIs",
                "version": "1.0.0",
                "permissions": ["nativeMessaging", "sidePanel"],
                "side_panel": [
                    "default_path": "side.html",
                ],
            ],
            files: [
                "side.html": "<!doctype html><title>Side</title>",
            ]
        )
        let runtimeReport = makeRuntimeLoadabilityReport(
            rootPath: root.path,
            id: "deferred-api-runtime-report"
        )
        let report = reportForStaticRoot(root, runtimeReport: runtimeReport)

        XCTAssertTrue(
            report.classificationCategories.contains(.runtimeContextStillBlocked)
        )
        XCTAssertFalse(
            report.classificationFindings.contains {
                $0.severity == .objectBlocking
            }
        )
        XCTAssertTrue(
            report.remainingRuntimeContextBlockers.contains {
                $0.contains("nativeMessaging")
                    || $0.contains("side_panel")
                    || $0.contains("runtime")
            }
        )
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testPasswordManagerLikeFixtureReportsRuntimeAndNativeBlockers()
        throws
    {
        let written = try writeBundle(
            named: "object-acceptance-password-manager",
            manifest: [
                "manifest_version": 3,
                "name": "Password Manager Like",
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
            ],
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
                "content.js": "chrome.runtime.sendMessage({type: 'probe'});\n",
                "popup.html": "<!doctype html><html><head></head><body>Popup</body></html>",
            ]
        )
        let variant = try writeVariant(for: written)
        let runtimeReport = try readReport(from: variant.variantRootURL)
        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: written.storeRootURL)
        let candidate = try XCTUnwrap(inventory.candidates.first)
            .profileHostCandidate

        let report = reportForCandidate(
            candidate,
            runtimeReport: runtimeReport
        )

        XCTAssertTrue(report.staticInspection.installReportDeferredAPIs.contains(.nativeMessaging))
        XCTAssertTrue(
            report.classificationCategories.contains(.runtimeContextStillBlocked)
        )
        XCTAssertTrue(
            report.remainingRuntimeContextBlockers.contains {
                $0.localizedCaseInsensitiveContains("native")
            }
        )
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testTeardownReleasesProbedObjectStateWithoutDeletingArtifacts()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let fixture = try makeGeneratedRewrittenFixture(
            named: "object-probe-teardown"
        )
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                resourceBaseURLPath: fixture.variantRootURL.path,
                generatedBundleID: fixture.candidate.id,
                generatedBundleHash:
                    fixture.candidate.rewrittenManifestSHA256,
                runtimeLoadabilityReportID: fixture.report.id,
                runtimeLoadabilityReportPath:
                    fixture.candidate.runtimeLoadabilityReportPath,
                runtimeLoadabilityReportSHA256:
                    fixture.candidate.runtimeLoadabilityReportSHA256,
                staticRuntimeBlockers: fixture.report.blockers
            )
        )
        let owner = ChromeMV3ExtensionObjectProbeOwner(
            gateDecision: decision
        )
        _ = await owner.runProbeIfAllowed()

        let teardown = owner.tearDown()

        XCTAssertEqual(teardown.state, .released)
        XCTAssertFalse(teardown.extensionObjectCreated)
        XCTAssertEqual(teardown.contextCount, 0)
        XCTAssertEqual(teardown.controllerLoadCount, 0)
        XCTAssertFalse(teardown.generatedBundleLoadedIntoController)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.variantRootURL.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.variantRootURL
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
    }

    @MainActor
    func testProfileDiagnosticsReportProbeStatusNarrowly() async throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension object probing requires macOS 15.5 in Sumi tests.")
        }

        let fixture = try makeGeneratedRewrittenFixture(
            named: "object-probe-profile-diagnostics"
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ChromeMV3ExtensionObjectModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let probeDiagnosticsOptional = await module
            .runChromeMV3ExtensionObjectProbeIfEnabled(
                explicitInternalExtensionObjectProbeAllowed: true,
                candidate: fixture.candidate,
                runtimeLoadabilityReport: fixture.report
        )
        let probeDiagnostics = try XCTUnwrap(probeDiagnosticsOptional)
        let hostDiagnostics = try XCTUnwrap(
            module.chromeMV3InventoryDiagnosticsIfEnabled(
                rootURL: fixture.storeRootURL
            )
        )

        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(
            hostDiagnostics.extensionObjectProbeDiagnostics?.state,
            probeDiagnostics.state
        )
        XCTAssertEqual(
            hostDiagnostics.extensionObjectProbeDiagnostics?.contextCount,
            0
        )
        XCTAssertEqual(
            hostDiagnostics.extensionObjectProbeDiagnostics?.controllerLoadCount,
            0
        )
        XCTAssertEqual(
            hostDiagnostics.extensionObjectProbeDiagnostics?.runtimeLoadable,
            false
        )
        XCTAssertEqual(
            hostDiagnostics.extensionObjectAcceptanceReport?.probeResult,
            probeDiagnostics.state
        )
        XCTAssertEqual(
            hostDiagnostics.extensionObjectAcceptanceReport?.runtimeLoadable,
            false
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.variantRootURL
                    .appendingPathComponent(
                        ChromeMV3WebKitObjectAcceptanceReportWriter
                            .reportFileName
                    )
                    .path
            )
        )
    }

    func testSourceGuardAllowsWKWebExtensionCreationOnlyInObjectProbeRunner()
        throws
    {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        let creationFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            creationFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let chromeMV3Source = sourceFiles
            .filter {
                $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
            }
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

        let forbiddenRegexes = [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
        ]
        for forbiddenRegex in forbiddenRegexes {
            XCTAssertNil(
                chromeMV3Source.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private struct ProbeFixture {
        var storeRootURL: URL
        var variantRootURL: URL
        var candidate: ChromeMV3RewrittenVariantCandidate
        var report: ChromeMV3RuntimeLoadabilityReport
    }

    private struct WrittenBundleFixture {
        var storeRootURL: URL
        var stage: ChromeMV3OriginalBundleStageResult
        var result: ChromeMV3GeneratedBundleWriteResult
        var runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
        var preview: ChromeMV3ManifestRewritePreview
        var dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport
    }

    private func makeGeneratedRewrittenFixture(
        named name: String
    ) throws -> ProbeFixture {
        let written = try writeBundle(
            named: name,
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        let variant = try writeVariant(for: written)
        let report = try readReport(from: variant.variantRootURL)
        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: written.storeRootURL)
        let candidate = try XCTUnwrap(inventory.candidates.first)
            .profileHostCandidate

        return ProbeFixture(
            storeRootURL: written.storeRootURL,
            variantRootURL: variant.variantRootURL,
            candidate: candidate,
            report: report
        )
    }

    private func writeBundle(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> WrittenBundleFixture {
        let sourceURL = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let storeRootURL = try makeTemporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRootURL,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: sourceURL)
        let result = try ChromeMV3GeneratedBundleWriter(rootURL: storeRootURL)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let decoder = JSONDecoder()
        let runtimeResourcePlan = try decoder.decode(
            ChromeMV3RuntimeResourcePlan.self,
            from: Data(
                contentsOf: result.generatedBundleRootURL
                    .appendingPathComponent("runtime-resource-plan.json")
            )
        )
        let preview = try decoder.decode(
            ChromeMV3ManifestRewritePreview.self,
            from: Data(contentsOf: result.manifestRewritePreviewURL)
        )
        let dryRunReport = try decoder.decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            from: Data(contentsOf: result.manifestRewriteDryRunReportURL)
        )
        return WrittenBundleFixture(
            storeRootURL: storeRootURL,
            stage: stage,
            result: result,
            runtimeResourcePlan: runtimeResourcePlan,
            preview: preview,
            dryRunReport: dryRunReport
        )
    }

    private func writeVariant(
        for fixture: WrittenBundleFixture
    ) throws -> ChromeMV3GeneratedRewriteVariantWriteResult {
        try ChromeMV3GeneratedRewriteVariantWriter().writeRewrittenVariant(
            generatedBundleRecord: fixture.result.record,
            generatedBundleRootURL: fixture.result.generatedBundleRootURL,
            runtimeResourcePlan: fixture.runtimeResourcePlan,
            manifestRewritePreview: fixture.preview,
            dryRunReport: fixture.dryRunReport
        )
    }

    private func gateInput(
        extensionsModuleEnabled: Bool = true,
        profileHostModuleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalExtensionObjectProbeAllowed: Bool = true,
        resourceBaseURLPath: String? = "/tmp/sumi/generated-rewritten",
        generatedBundleID: String? = "generated-candidate",
        generatedBundleHash: String? = String(repeating: "a", count: 64),
        generatedRewrittenBundleExists: Bool = true,
        runtimeLoadabilityReportExists: Bool = true,
        runtimeLoadabilityReportID: String? = "runtime-loadability-test",
        runtimeLoadabilityReportPath: String? =
            "/tmp/sumi/generated-rewritten/runtime-loadability-report.json",
        runtimeLoadabilityReportSHA256: String? =
            String(repeating: "b", count: 64),
        manifestVersion: Int? = 3,
        runtimeLoadable: Bool? = false,
        staticRuntimeBlockers: [String] = [],
        requestedContextCreation: Bool = false,
        requestedContextLoading: Bool = false,
        requestedControllerLoad: Bool = false,
        requestedExtensionCodeExecution: Bool = false,
        requestedUserScriptRegistration: Bool = false,
        requestedNativeMessagingLaunch: Bool = false,
        staleAttachedWebViewCount: Int = 0
    ) -> ChromeMV3ExtensionObjectProbeGateInput {
        ChromeMV3ExtensionObjectProbeGateInput(
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostModuleState: profileHostModuleState,
            explicitInternalExtensionObjectProbeAllowed:
                explicitInternalExtensionObjectProbeAllowed,
            resourceBaseURLPath: resourceBaseURLPath,
            generatedBundleID: generatedBundleID,
            generatedBundleHash: generatedBundleHash,
            generatedRewrittenBundleExists: generatedRewrittenBundleExists,
            runtimeLoadabilityReportExists: runtimeLoadabilityReportExists,
            runtimeLoadabilityReportID: runtimeLoadabilityReportID,
            runtimeLoadabilityReportPath: runtimeLoadabilityReportPath,
            runtimeLoadabilityReportSHA256: runtimeLoadabilityReportSHA256,
            manifestVersion: manifestVersion,
            runtimeLoadable: runtimeLoadable,
            staticRuntimeBlockers: staticRuntimeBlockers,
            requestedContextCreation: requestedContextCreation,
            requestedContextLoading: requestedContextLoading,
            requestedControllerLoad: requestedControllerLoad,
            requestedExtensionCodeExecution: requestedExtensionCodeExecution,
            requestedUserScriptRegistration: requestedUserScriptRegistration,
            requestedNativeMessagingLaunch: requestedNativeMessagingLaunch,
            staleAttachedWebViewCount: staleAttachedWebViewCount
        )
    }

    private func makeRuntimeLoadabilityReport(
        rootPath: String,
        id: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        let checks = [
            ChromeMV3RuntimeLoadabilityCheck(
                category: .manifestShape,
                status: .passed,
                message: "Rewritten manifest exists and declares manifest_version 3.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .runtimeTemplateFileHashes,
                status: .passed,
                message: "Runtime template file hashes were recorded.",
                relatedPaths: ["_sumi_runtime/chrome-shim.common.js"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .unsupportedAPIs,
                status: .passed,
                message: "Unsupported API classifications are represented.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .deferredAPIs,
                status: .deferred,
                message: "Deferred APIs remain planning-only.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .WebKitRuntimeNotWired,
                status: .deferred,
                message: "WebKit runtime loading is intentionally not wired.",
                relatedPaths: [],
                details: []
            ),
        ]

        return ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: id,
            generatedVariantRootPath: rootPath,
            generatedVariantRootRelativeName: "generated-rewritten",
            sourceApplicationReportHash: nil,
            rewrittenManifestHash: ChromeMV3RuntimeLoadabilityFileHash(
                relativePath: "manifest.json",
                sha256: String(repeating: "1", count: 64),
                byteCount: 128
            ),
            runtimeTemplateFileHashes: [
                ChromeMV3RuntimeLoadabilityFileHash(
                    relativePath: "_sumi_runtime/chrome-shim.common.js",
                    sha256: String(repeating: "2", count: 64),
                    byteCount: 64
                ),
            ],
            extensionPageRewrittenFileHashes: [],
            extensionPageStaticChecks: [],
            verificationChecks: checks,
            passedChecks: [.manifestShape, .runtimeTemplateFileHashes, .unsupportedAPIs],
            failedChecks: [],
            deferredChecks: [.deferredAPIs, .WebKitRuntimeNotWired],
            warnings: [],
            missing: [],
            blockers: [
                "WebKit runtime loading is not yet wired.",
            ],
            unsupportedAPIs: [],
            deferredAPIs: [.runtime],
            requiredFutureRuntimeComponents: [
                "Future context loading must wait for verified runtime messaging.",
            ],
            passwordManagerReadiness:
                ChromeMV3PasswordManagerRuntimeReadinessReport(
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
            structurallyValid: true,
            runtimeLoadable: false,
            runtimeLoadableFalseReason: "Non-loading test fixture.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func serviceWorkerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func makeFixture(
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

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        try makeFixture(named: name, manifest: manifest, files: files)
    }

    private func makeCandidate(
        rootURL: URL,
        id: String = "static-object-acceptance-candidate"
    ) -> ChromeMV3RewrittenVariantCandidate {
        ChromeMV3RewrittenVariantCandidate(
            id: id,
            generatedVariantRootPath: nil,
            rewrittenVariantRootPath: rootURL.standardizedFileURL.path,
            runtimeLoadabilityReportPath: nil,
            rewrittenManifestSHA256: nil,
            runtimeLoadabilityReportSHA256: nil,
            manifestVersion: 3,
            rewrittenVariantExists: FileManager.default.fileExists(
                atPath: rootURL.path
            )
        )
    }

    private func reportForStaticRoot(
        _ rootURL: URL,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport? = nil
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        reportForCandidate(
            makeCandidate(rootURL: rootURL),
            runtimeReport: runtimeReport
        )
    }

    private func reportForCandidate(
        _ candidate: ChromeMV3RewrittenVariantCandidate,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport?
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        let decision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: gateInput(
                resourceBaseURLPath: candidate.rewrittenVariantRootPath,
                generatedBundleID: candidate.id,
                generatedBundleHash: candidate.rewrittenManifestSHA256,
                generatedRewrittenBundleExists: candidate.rewrittenVariantExists,
                runtimeLoadabilityReportExists: runtimeReport != nil,
                runtimeLoadabilityReportID: runtimeReport?.id,
                runtimeLoadabilityReportPath:
                    candidate.runtimeLoadabilityReportPath,
                runtimeLoadabilityReportSHA256:
                    candidate.runtimeLoadabilityReportSHA256,
                manifestVersion: candidate.manifestVersion,
                runtimeLoadable: runtimeReport?.runtimeLoadable ?? false,
                staticRuntimeBlockers: runtimeReport?.blockers ?? []
            )
        )
        return ChromeMV3WebKitObjectAcceptanceReportGenerator
            .makeReport(
                candidate: candidate,
                gateDecision: decision,
                probeDiagnostics: nil,
                runtimeLoadabilityReport: runtimeReport
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

    private func readReport(
        from variantRootURL: URL
    ) throws -> ChromeMV3RuntimeLoadabilityReport {
        try JSONDecoder().decode(
            ChromeMV3RuntimeLoadabilityReport.self,
            from: Data(
                contentsOf: variantRootURL
                    .appendingPathComponent(
                        ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                    )
            )
        )
    }

    @MainActor
    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: ChromeMV3ExtensionObjectModuleProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let initialProfile = Profile(name: "Chrome MV3 Object Probe Test")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
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

private final class ChromeMV3ExtensionObjectModuleProbe {
    var managerCount = 0
}
