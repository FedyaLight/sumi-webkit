import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ContextCreationGateTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksContextCreationAndWritesNoReport()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-disabled")
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ContextCreationModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let report = module.chromeMV3ContextCreationGateReportIfEnabled(
            explicitInternalContextCreationAllowed: true,
            candidate: candidate,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ChromeMV3ContextCreationGateReportWriter.reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testMissingExplicitInternalFlagBlocksContextCreation()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-flag")
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                explicitInternalContextCreationAllowed: false
            )
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(
            decision.blockers.contains(.explicitContextCreationNotAllowed)
        )
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canExecuteExtensionCodeNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    @MainActor
    func testMissingAcceptedWKWebExtensionObjectBlocksContextCreation()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-no-object")
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                acceptedWebExtensionObjectAvailable: false
            )
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(
            decision.blockers.contains(.acceptedExtensionObjectUnavailable)
        )
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    @MainActor
    func testObjectNotAcceptedByWebKitBlocksContextCreation()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-rejected")
        let rejectedReport = makeObjectAcceptanceReport(
            rootURL: root,
            accepted: false
        )
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                objectAcceptanceReport: rejectedReport
            )
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(decision.blockers.contains(.webKitObjectNotAccepted))
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canExecuteExtensionCodeNow)
    }

    @MainActor
    func testMissingEmptyControllerOwnerBlocksContextCreation()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-no-owner")
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                includeEmptyControllerDiagnostics: false
            )
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(
            decision.blockers.contains(.emptyControllerDiagnosticsMissing)
        )
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    @MainActor
    func testUnresolvedAndMismatchedDataStoreIdentityBlock()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let unresolvedRoot = try makeSimpleRewrittenRoot(
            named: "context-create-unresolved-store"
        )
        let unresolvedDecision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: unresolvedRoot,
                profileIdentifier:
                    ChromeMV3ProfileHost.unresolvedProfileIdentifier,
                emptyControllerDiagnostics:
                    makeUnresolvedControllerDiagnostics()
            )
        )

        XCTAssertFalse(unresolvedDecision.canCreateContextObjectNow)
        XCTAssertTrue(
            unresolvedDecision.blockers.contains(.profileIdentityUnavailable)
        )
        XCTAssertTrue(
            unresolvedDecision.blockers.contains(
                .controllerDataStoreIdentityUnresolved
            )
        )

        let mismatchRoot = try makeSimpleRewrittenRoot(
            named: "context-create-mismatched-store"
        )
        let mismatchDecision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: mismatchRoot,
                emptyControllerDiagnostics:
                    try makeCreatedEmptyControllerDiagnostics(
                        dataStoreIdentity:
                            .profileIdentifier(UUID().uuidString)
                    )
            )
        )

        XCTAssertFalse(mismatchDecision.canCreateContextObjectNow)
        XCTAssertTrue(
            mismatchDecision.blockers.contains(
                .controllerDataStoreIdentityMismatch
            )
        )
        XCTAssertFalse(mismatchDecision.runtimeLoadable)
    }

    @MainActor
    func testStaleAttachedWebViewsBlockContextCreation()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-stale")
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                liveNormalTabAttachmentSnapshot: staleSnapshot()
            )
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(
            decision.blockers.contains(.staleAttachedWebViewsPresent)
        )
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canExecuteExtensionCodeNow)
    }

    @MainActor
    func testRuntimeBridgePrerequisitesAndJSExposureAreSeparated()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-runtime")
        let readiness = try makeRuntimeBridgeReadinessReport(rootURL: root)
        let summary =
            ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary.make(
                readinessReport: readiness
            )

        XCTAssertEqual(summary.status, .modeledForContextObjectCreation)
        XCTAssertTrue(summary.messagingDispatcherModelExists)
        XCTAssertTrue(summary.jsBridgeContractExists)
        XCTAssertFalse(summary.jsBridgeExposedToJSNow)
        XCTAssertTrue(summary.jsBridgeInjectionUnavailable)
        XCTAssertTrue(summary.storageModelExists)
        XCTAssertTrue(summary.permissionBrokerExists)
        XCTAssertTrue(summary.serviceWorkerLifecycleCoordinatorExists)
        XCTAssertTrue(summary.serviceWorkerWakeUnavailable)
        XCTAssertTrue(summary.nativeMessagingBlocked)
        XCTAssertTrue(summary.nativeMessagingProcessLaunchUnavailable)
        XCTAssertTrue(summary.listenerRegistrationUnavailable)
        XCTAssertFalse(summary.runtimeLoadable)

        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                runtimeBridgeReadinessReport: readiness
            )
        )
        XCTAssertTrue(decision.canCreateContextObjectNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canExecuteExtensionCodeNow)
        XCTAssertFalse(decision.runtimeLoadable)
    }

    @MainActor
    func testSDKUnsupportedDiagnosticBlocksWithoutFakeContext()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-sdk")
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                sdkCompatibility: .unsupported(
                    finding:
                        "Test SDK shape does not expose detached context construction."
                )
            )
        )
        let owner = ChromeMV3DetachedContextOwner(gateDecision: decision)
        let diagnostics = owner.createDetachedContextIfAllowed(
            acceptedWebExtension: nil
        )
        let report = ChromeMV3ContextCreationGateReportGenerator.makeReport(
            decision: decision,
            detachedContextOwnerDiagnostics: diagnostics
        )

        XCTAssertFalse(decision.canCreateContextObjectNow)
        XCTAssertTrue(
            decision.blockers.contains(.sdkDetachedConstructionUnsupported)
        )
        XCTAssertEqual(diagnostics.state, .blocked)
        XCTAssertFalse(diagnostics.contextObjectCreated)
        XCTAssertFalse(report.contextObjectCreated)
        XCTAssertEqual(
            report.sdkCompatibilityStatus.status,
            .unsupportedByCurrentSDKShape
        )
        XCTAssertFalse(report.contextLoadedIntoController)
        XCTAssertFalse(report.runtimeLoadable)
    }

    @MainActor
    func testAcceptedObjectCanCreateDetachedContextWhenSDKSupportsIt()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context object creation requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "context-create-detached",
            manifest: [
                "manifest_version": 3,
                "name": "Detached Context",
                "version": "1.0.0",
            ],
            files: [:]
        )
        let runtimeReport = makeRuntimeLoadabilityReport(rootPath: root.path)
        let candidate = makeCandidate(rootURL: root)
        let objectDecision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: objectProbeGateInput(
                rootURL: root,
                candidate: candidate,
                runtimeReport: runtimeReport
            )
        )
        let probeOwner = ChromeMV3ExtensionObjectProbeOwner(
            gateDecision: objectDecision
        )
        let probeDiagnostics = await probeOwner.runProbeIfAllowed()
        guard probeDiagnostics.state == .created else {
            throw XCTSkip(
                "WKWebExtension object probe did not create an object with the active SDK: \(probeDiagnostics.error?.message ?? "unknown")"
            )
        }

        let objectReport =
            ChromeMV3WebKitObjectAcceptanceReportGenerator.makeReport(
                candidate: candidate,
                gateDecision: objectDecision,
                probeDiagnostics: probeDiagnostics,
                runtimeLoadabilityReport: runtimeReport
            )
        let readiness = try makeRuntimeBridgeReadinessReport(
            rootURL: root,
            runtimeLoadabilityReport: runtimeReport,
            objectAcceptanceReport: objectReport
        )
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(
                rootURL: root,
                objectProbeDiagnostics: probeDiagnostics,
                objectAcceptanceReport: objectReport,
                runtimeBridgeReadinessReport: readiness
            )
        )
        let acceptedObject = probeOwner
            .acceptedWebExtensionObjectForDetachedContext(
                objectAcceptanceReport: objectReport
            )
        let owner = ChromeMV3DetachedContextOwner(gateDecision: decision)

        let diagnostics = owner.createDetachedContextIfAllowed(
            acceptedWebExtension: acceptedObject
        )

        XCTAssertTrue(decision.canCreateContextObjectNow)
        XCTAssertEqual(diagnostics.state, .createdDetached)
        XCTAssertTrue(diagnostics.contextObjectCreated)
        XCTAssertFalse(diagnostics.contextLoadedIntoController)
        XCTAssertEqual(diagnostics.controllerLoadCount, 0)
        XCTAssertFalse(diagnostics.extensionCodeExecuted)
        XCTAssertEqual(diagnostics.serviceWorkerWakeCount, 0)
        XCTAssertEqual(diagnostics.scriptInjectionCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canExecuteExtensionCodeNow)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertNotNil(owner.detachedContext)
        XCTAssertFalse(try XCTUnwrap(owner.detachedContext).isLoaded)
        XCTAssertNil(owner.detachedContext?.webExtensionController)

        let report = ChromeMV3ContextCreationGateReportGenerator.makeReport(
            decision: decision,
            detachedContextOwnerDiagnostics: diagnostics
        )
        XCTAssertTrue(report.contextObjectCreated)
        XCTAssertFalse(report.contextLoadedIntoController)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.canExecuteExtensionCodeNow)
        XCTAssertFalse(report.extensionCodeExecuted)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(
            report.sameControllerWebViewPrecondition
                .futureContextControllerMustMatchTabWebViews,
            true
        )

        let teardown = owner.tearDown()
        XCTAssertEqual(teardown.state, .released)
        XCTAssertFalse(teardown.contextObjectCreated)
        XCTAssertNil(owner.detachedContext)
        XCTAssertFalse(teardown.generatedArtifactsDeleted)
        XCTAssertFalse(teardown.websiteDataCleared)
        XCTAssertFalse(teardown.existingWebViewsDetachedOrReattached)
        XCTAssertFalse(teardown.emptyControllerAffectedByTeardown)
    }

    @MainActor
    func testReportWriterIsDeterministicAndModuleIntegratesDiagnostics()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 context creation gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "context-create-report")
        let candidate = makeCandidate(rootURL: root)
        let decision = ChromeMV3ContextCreationGate.evaluate(
            input: try gateInput(rootURL: root)
        )
        let diagnostics = ChromeMV3DetachedContextOwnerDiagnostics.make(
            state: .notCreated,
            gateDecision: decision,
            contextObjectCreated: false
        )
        let first = ChromeMV3ContextCreationGateReportGenerator.makeReport(
            decision: decision,
            detachedContextOwnerDiagnostics: diagnostics
        )
        try ChromeMV3ContextCreationGateReportWriter.write(
            first,
            toRewrittenBundleRoot: root
        )
        let firstData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContextCreationGateReportWriter.reportFileName
            )
        )
        let second = ChromeMV3ContextCreationGateReportGenerator.makeReport(
            decision: decision,
            detachedContextOwnerDiagnostics: diagnostics
        )
        try ChromeMV3ContextCreationGateReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ContextCreationGateReportWriter.reportFileName
            )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            first.reportFileName,
            ChromeMV3ContextCreationGateReportWriter.reportFileName
        )
        XCTAssertTrue(first.canCreateContextObjectNow)
        XCTAssertFalse(first.contextObjectCreated)
        XCTAssertFalse(first.canLoadContextNow)
        XCTAssertFalse(first.runtimeLoadable)

        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ContextCreationModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )
        let moduleReport = try XCTUnwrap(
            module.chromeMV3ContextCreationGateReportIfEnabled(
                explicitInternalContextCreationAllowed: true,
                candidate: candidate,
                objectAcceptanceReport:
                    makeObjectAcceptanceReport(rootURL: root, accepted: true),
                runtimeBridgeReadinessReport:
                    try makeRuntimeBridgeReadinessReport(rootURL: root),
                writeReport: true
            )
        )
        let hostDiagnostics = module.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertEqual(
            hostDiagnostics?.contextCreationGateReport,
            moduleReport
        )
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testSourceGuardsForContextCreationGateStayNonExecuting()
        throws
    {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ]).filter {
            $0.relativePath.contains("ChromeMV3")
        }
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
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerRealPackageCompatibility.swift",
            "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift",
            "SumiTests/ChromeMV3PasswordManagerRealPackageCompatibilityTests.swift",
        ]
        let chromeMV3Source = sourceFiles
            .filter { source in
                runtimeJSBridgeScopedFiles.contains {
                    source.relativePath.hasSuffix($0)
                } == false
            }
            .map(\.contents)
            .joined(separator: "\n")

        let contextInitFiles = sourceFiles
            .filter {
                $0.contents.contains(
                    "WKWebExtension" + "Context.init(for:"
                )
            }
            .map(\.relativePath)
            .sorted()
        XCTAssertEqual(
            contextInitFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3DetachedContextOwner.swift",
            ]
        )
        XCTAssertFalse(
            chromeMV3Source.contains("WKWebExtension" + "Context(")
        )

        for forbidden in [
            "load" + "ExtensionContext",
            "WKUser" + "Script(",
            "add" + "UserScript",
            "add" + "ScriptMessageHandler",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(chromeMV3Source.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "context" + "LoadedIntoController\\s*[:=].*" + "tr" + "ue",
            "canExecute" + "ExtensionCodeNow\\s*[:=].*" + "tr" + "ue",
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

    @MainActor
    private func gateInput(
        rootURL: URL,
        profileIdentifier: String = UUID().uuidString,
        extensionsModuleEnabled: Bool = true,
        profileHostModuleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalContextCreationAllowed: Bool = true,
        acceptedWebExtensionObjectAvailable: Bool = true,
        objectProbeDiagnostics:
            ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport? = nil,
        includeEmptyControllerDiagnostics: Bool = true,
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics? = nil,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport? = nil,
        sdkCompatibility: ChromeMV3ContextCreationSDKCompatibility =
            .currentAppleSDK
    ) throws -> ChromeMV3ContextCreationGateInput {
        let candidate = makeCandidate(rootURL: rootURL)
        let runtimeReport = makeRuntimeLoadabilityReport(rootPath: rootURL.path)
        let resolvedObjectReport = objectAcceptanceReport
            ?? makeObjectAcceptanceReport(
                rootURL: rootURL,
                accepted: true,
                runtimeReport: runtimeReport
            )
        let resolvedEmptyController:
            ChromeMV3EmptyControllerDiagnostics?
        if !includeEmptyControllerDiagnostics {
            resolvedEmptyController = nil
        } else if let emptyControllerDiagnostics {
            resolvedEmptyController = emptyControllerDiagnostics
        } else {
            resolvedEmptyController = try makeCreatedEmptyControllerDiagnostics(
                profileIdentifier: profileIdentifier
            )
        }
        let emptyControllerForReadiness = try resolvedEmptyController
            ?? makeCreatedEmptyControllerDiagnostics(
                profileIdentifier: profileIdentifier
            )
        let resolvedReadiness: ChromeMV3RuntimeBridgeReadinessReport
        if let runtimeBridgeReadinessReport {
            resolvedReadiness = runtimeBridgeReadinessReport
        } else {
            resolvedReadiness = try makeRuntimeBridgeReadinessReport(
                rootURL: rootURL,
                runtimeLoadabilityReport: runtimeReport,
                objectAcceptanceReport: resolvedObjectReport,
                emptyControllerDiagnostics: emptyControllerForReadiness
            )
        }

        return ChromeMV3ContextCreationGateInput(
            candidateID: candidate.id,
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostModuleState: profileHostModuleState,
            profileIdentifier: profileIdentifier,
            explicitInternalContextCreationAllowed:
                explicitInternalContextCreationAllowed,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            objectProbeDiagnostics: objectProbeDiagnostics,
            objectAcceptanceReport: resolvedObjectReport,
            emptyControllerDiagnostics: resolvedEmptyController,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport: resolvedReadiness,
            sdkCompatibility: sdkCompatibility,
            requestedContextLoading: false,
            requestedControllerLoad: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false
        )
    }

    private func makeObjectAcceptanceReport(
        rootURL: URL,
        accepted: Bool,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport? = nil
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        let candidate = makeCandidate(rootURL: rootURL)
        let runtimeReport = runtimeReport
            ?? makeRuntimeLoadabilityReport(rootPath: rootURL.path)
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
                        domain: "SumiTests.ContextCreation",
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

    @MainActor
    private func makeCreatedEmptyControllerDiagnostics(
        profileIdentifier: String = UUID().uuidString,
        dataStoreIdentity: ChromeMV3ProfileDataStoreIdentity? = nil
    ) throws -> ChromeMV3EmptyControllerDiagnostics {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Empty controller diagnostics require macOS 15.5.")
        }

        let identifier = UUID(uuidString: profileIdentifier) ?? UUID()
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
                    dataStoreIdentity
                    ?? .profileIdentifier(profileIdentifier),
                disabledRuntimeInvariantStatus: .satisfied
            )
        )
        let owner = try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: decision,
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: identifier
            )
        )
        return owner.diagnostics()
    }

    private func makeUnresolvedControllerDiagnostics()
        -> ChromeMV3EmptyControllerDiagnostics
    {
        let decision = ChromeMV3ControllerCreationGate.evaluate(
            input: ChromeMV3ControllerCreationGateInput(
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileHostControllerState: .absentNotCreated,
                explicitControllerCreationAllowed: true,
                requestedContextLoading: false,
                requestedNormalTabAttachment: false,
                profileIdentifier:
                    ChromeMV3ProfileHost.unresolvedProfileIdentifier,
                profileDataStoreIdentity: .unresolved,
                disabledRuntimeInvariantStatus: .satisfied
            )
        )
        return ChromeMV3EmptyControllerDiagnostics.notCreated(
            gateDecision: decision
        )
    }

    @MainActor
    private func makeRuntimeBridgeReadinessReport(
        rootURL: URL,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport? = nil,
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport? = nil,
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics? = nil
    ) throws -> ChromeMV3RuntimeBridgeReadinessReport {
        let runtimeReport = runtimeLoadabilityReport
            ?? makeRuntimeLoadabilityReport(rootPath: rootURL.path)
        let objectReport = objectAcceptanceReport
            ?? makeObjectAcceptanceReport(
                rootURL: rootURL,
                accepted: true,
                runtimeReport: runtimeReport
            )
        let emptyController: ChromeMV3EmptyControllerDiagnostics
        if let emptyControllerDiagnostics {
            emptyController = emptyControllerDiagnostics
        } else {
            emptyController = try makeCreatedEmptyControllerDiagnostics()
        }
        let contextReport = ChromeMV3ContextReadinessReportGenerator
            .makeReport(
                candidate: makeCandidate(rootURL: rootURL),
                objectAcceptanceReport: objectReport,
                emptyControllerDiagnostics: emptyController,
                runtimeLoadabilityReport: runtimeReport
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

    private func staleSnapshot()
        -> ChromeMV3LiveNormalTabAttachmentRecorderSnapshot
    {
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot(
            recentDecisions: [],
            attachedConfigurationCount: 1,
            createdAttachedWebViewCount: 1,
            staleOrNeedsRecreationCount: 1,
            attachedTabDiagnosticIdentifiers: ["tab-attached"],
            staleOrNeedsRecreationTabDiagnosticIdentifiers: ["tab-stale"],
            accidentallyAttachedAuxiliarySurface: false,
            auxiliaryAttachmentSequenceNumbers: [],
            runtimeLoadable: false,
            canLoadContextNow: false,
            contextCount: 0,
            contextLoadCalled: false,
            webExtensionCreated: true,
            webExtensionContextCreated: false,
            generatedExtensionBundleLoaded: false,
            nativeMessagingLaunched: false,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false
        )
    }

    private func makeRuntimeLoadabilityReport(
        rootPath: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-context-creation-test",
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
                    contentScriptsPresent: false,
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
            runtimeLoadableFalseReason: "Context creation gate test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Context Creation",
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
        id: String = "context-creation-candidate"
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
        probe: ContextCreationModuleProbe
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
private final class ContextCreationModuleProbe {
    let profile = Profile(name: "Chrome MV3 Context Creation Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
