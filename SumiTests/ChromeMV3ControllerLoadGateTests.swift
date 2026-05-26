import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ControllerLoadGateTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksControllerLoadAndWritesNoReport() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "load-disabled")
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ControllerLoadModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let report = module.chromeMV3ControllerLoadGateReportIfEnabled(
            explicitInternalControllerLoadProbeAllowed: true,
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
                    ChromeMV3ControllerLoadGateReportWriter.reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testMinimalInertFixturePolicyAcceptsOnlyEmptyMV3Manifest() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "load-minimal")
        let policy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: root.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )

        XCTAssertTrue(policy.loadSafeForMinimalInertFixture)
        XCTAssertEqual(policy.manifestVersion, 3)
        XCTAssertTrue(policy.blockers.isEmpty)
        XCTAssertTrue(policy.declaredPermissions.isEmpty)
        XCTAssertEqual(policy.contentScriptCount, 0)
        XCTAssertNil(policy.backgroundServiceWorkerPath)
    }

    @MainActor
    func testNonMinimalFixturesBlockControllerLoadPolicy() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let nativeRoot = try makeSimpleRewrittenRoot(
            named: "load-native",
            manifest: [
                "manifest_version": 3,
                "name": "Native",
                "version": "1.0.0",
                "permissions": ["nativeMessaging"],
            ]
        )
        let contentRoot = try makeSimpleRewrittenRoot(
            named: "load-content",
            manifest: [
                "manifest_version": 3,
                "name": "Content",
                "version": "1.0.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                    ],
                ],
            ],
            files: ["content.js": ""]
        )
        let workerRoot = try makeSimpleRewrittenRoot(
            named: "load-worker",
            manifest: [
                "manifest_version": 3,
                "name": "Worker",
                "version": "1.0.0",
                "background": ["service_worker": "service_worker.js"],
            ],
            files: ["service_worker.js": ""]
        )

        let nativePolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: nativeRoot.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
        let contentPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: contentRoot.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
        let workerPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: workerRoot.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )

        XCTAssertFalse(nativePolicy.loadSafeForMinimalInertFixture)
        XCTAssertTrue(
            nativePolicy.blockers.contains(
                .nativeMessagingPermissionPresent
            )
        )
        XCTAssertFalse(contentPolicy.loadSafeForMinimalInertFixture)
        XCTAssertTrue(contentPolicy.blockers.contains(.contentScriptsPresent))
        XCTAssertFalse(workerPolicy.loadSafeForMinimalInertFixture)
        XCTAssertTrue(
            workerPolicy.blockers.contains(.backgroundServiceWorkerPresent)
        )
        XCTAssertTrue(
            workerPolicy.blockers.contains(.serviceWorkerWrapperFilePresent)
        )
    }

    @MainActor
    func testMissingExplicitFlagDetachedContextObjectAndControllerBlockLoad()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "load-blockers")
        let missingFlag = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: root,
                explicitInternalControllerLoadProbeAllowed: false
            )
        )
        let missingContext = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: root,
                detachedContextDiagnostics: nil
            )
        )
        let missingObject = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: root,
                acceptedWebExtensionObjectAvailable: false
            )
        )
        let missingController = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: root,
                emptyControllerDiagnostics: nil
            )
        )

        XCTAssertFalse(missingFlag.loadAttemptAllowed)
        XCTAssertTrue(
            missingFlag.blockers.contains(
                .explicitControllerLoadProbeNotAllowed
            )
        )
        XCTAssertFalse(missingContext.loadAttemptAllowed)
        XCTAssertTrue(
            missingContext.blockers.contains(
                .detachedContextDiagnosticsMissing
            )
        )
        XCTAssertFalse(missingObject.loadAttemptAllowed)
        XCTAssertTrue(
            missingObject.blockers.contains(
                .acceptedExtensionObjectUnavailable
            )
        )
        XCTAssertFalse(missingController.loadAttemptAllowed)
        XCTAssertTrue(
            missingController.blockers.contains(
                .emptyControllerDiagnosticsMissing
            )
        )
        for decision in [
            missingFlag,
            missingContext,
            missingObject,
            missingController,
        ] {
            XCTAssertFalse(decision.runtimeLoadable)
            XCTAssertFalse(decision.chromeRuntimeAvailableNow)
            XCTAssertFalse(decision.jsBridgeAvailableNow)
            XCTAssertFalse(decision.canExecuteExtensionCodeNow)
        }
    }

    @MainActor
    func testStaleWebViewsAndSDKSafetyBlockLoadDeterministically() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let staleRoot = try makeSimpleRewrittenRoot(named: "load-stale")
        let stale = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: staleRoot,
                liveNormalTabAttachmentSnapshot: staleSnapshot()
            )
        )
        let sdkRoot = try makeSimpleRewrittenRoot(named: "load-sdk")
        let sdkBlocked = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: sdkRoot,
                sdkCompatibility: .blockedBySDKSemantics(
                    finding:
                        "Synthetic SDK finding says controller loading cannot be contained."
                )
            )
        )

        XCTAssertFalse(stale.loadAttemptAllowed)
        XCTAssertTrue(stale.blockers.contains(.staleAttachedWebViewsPresent))
        XCTAssertTrue(
            stale.sameControllerValidation.staleAttachedWebViewsBlockLoad
        )
        XCTAssertFalse(sdkBlocked.loadAttemptAllowed)
        XCTAssertTrue(
            sdkBlocked.blockers.contains(.sdkControllerLoadUnsupported)
        )
        XCTAssertTrue(sdkBlocked.blockers.contains(.sdkControllerLoadUnsafe))
        XCTAssertEqual(
            sdkBlocked.input.sdkCompatibility.status,
            .blockedBySDKSemantics
        )
    }

    @MainActor
    func testAcceptedMinimalInertFixtureAttemptsControllerLoadWithoutRuntimeExposure()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller load requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(
            named: "load-attempt",
            manifest: [
                "manifest_version": 3,
                "name": "Controller Load",
                "version": "1.0.0",
            ]
        )
        let prepared = try await prepareAcceptedDetachedContext(rootURL: root)
        let decision = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(
                rootURL: root,
                objectProbeDiagnostics: prepared.probeDiagnostics,
                objectAcceptanceReport: prepared.objectAcceptanceReport,
                detachedContextDiagnostics: prepared.contextDiagnostics,
                emptyControllerDiagnostics:
                    prepared.emptyControllerOwner.diagnostics(),
                runtimeBridgeReadinessReport:
                    prepared.runtimeBridgeReadinessReport
            )
        )
        let owner = ChromeMV3ControllerLoadOwner(gateDecision: decision)

        let diagnostics = owner.loadContextIntoControllerIfAllowed(
            emptyControllerOwner: prepared.emptyControllerOwner,
            detachedContextOwner: prepared.detachedContextOwner,
            acceptedWebExtension: prepared.acceptedWebExtension
        )
        let report = ChromeMV3ControllerLoadGateReportGenerator.makeReport(
            decision: decision,
            loadOwnerDiagnostics: diagnostics
        )

        XCTAssertTrue(decision.canLoadContextIntoControllerNow)
        XCTAssertTrue(decision.loadAttemptAllowed)
        XCTAssertTrue(diagnostics.controllerLoadAttempted)
        XCTAssertEqual(diagnostics.controllerLoadCount, 1)
        XCTAssertTrue(
            diagnostics.state == .loadedIntoController
                || diagnostics.state == .failed,
            "Unexpected load state: \(diagnostics.state.rawValue)"
        )
        if diagnostics.state == .loadedIntoController {
            XCTAssertTrue(diagnostics.contextLoadedIntoController)
            XCTAssertTrue(report.contextLoadedIntoController)
            let teardown = owner.tearDown()
            XCTAssertEqual(teardown.state, .teardownComplete)
            XCTAssertTrue(teardown.teardownComplete)
            XCTAssertTrue(
                teardown.contextUnloadedFromController
                    || prepared.detachedContextOwner.detachedContext?
                    .isLoaded == false
            )
        } else {
            XCTAssertNotNil(diagnostics.webKitError)
            XCTAssertFalse(report.contextLoadedIntoController)
        }

        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.chromeRuntimeAvailableNow)
        XCTAssertFalse(report.jsBridgeAvailableNow)
        XCTAssertFalse(report.canExecuteExtensionCodeNow)
        XCTAssertFalse(report.extensionCodeExecuted)
        XCTAssertEqual(report.serviceWorkerWakeCount, 0)
        XCTAssertEqual(report.scriptInjectionCount, 0)
        XCTAssertEqual(report.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertFalse(diagnostics.chromeRuntimeAvailableNow)
        XCTAssertFalse(diagnostics.jsBridgeAvailableNow)
        XCTAssertFalse(diagnostics.canExecuteExtensionCodeNow)
        XCTAssertFalse(diagnostics.extensionCodeExecuted)
        XCTAssertEqual(diagnostics.serviceWorkerWakeCount, 0)
        XCTAssertEqual(diagnostics.scriptInjectionCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertTrue(
            report.sideEffectGuardDiagnostics
                .unverifiedWebKitInternalSideEffect
        )
    }

    @MainActor
    func testReportWriterIsDeterministicAndModuleIntegratesDiagnostics()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 controller-load gate requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "load-report")
        let candidate = makeCandidate(rootURL: root)
        let decision = ChromeMV3ControllerLoadGate.evaluate(
            input: try gateInput(rootURL: root)
        )
        let diagnostics = ChromeMV3ControllerLoadOwnerDiagnostics.make(
            state: .notAttempted,
            gateDecision: decision
        )
        let first = ChromeMV3ControllerLoadGateReportGenerator.makeReport(
            decision: decision,
            loadOwnerDiagnostics: diagnostics
        )
        try ChromeMV3ControllerLoadGateReportWriter.write(
            first,
            toRewrittenBundleRoot: root
        )
        let firstData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ControllerLoadGateReportWriter.reportFileName
            )
        )
        let second = ChromeMV3ControllerLoadGateReportGenerator.makeReport(
            decision: decision,
            loadOwnerDiagnostics: diagnostics
        )
        try ChromeMV3ControllerLoadGateReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3ControllerLoadGateReportWriter.reportFileName
            )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            first.reportFileName,
            ChromeMV3ControllerLoadGateReportWriter.reportFileName
        )
        XCTAssertTrue(first.loadAttemptAllowed)
        XCTAssertFalse(first.controllerLoadAttempted)
        XCTAssertFalse(first.contextLoadedIntoController)
        XCTAssertFalse(first.runtimeLoadable)

        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ControllerLoadModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)
        let moduleReport = try XCTUnwrap(
            module.chromeMV3ControllerLoadGateReportIfEnabled(
                explicitInternalControllerLoadProbeAllowed: true,
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

        XCTAssertEqual(hostDiagnostics?.controllerLoadGateReport, moduleReport)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testSourceGuardsForControllerLoadBoundary() throws {
        let chromeMV3Source = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let testSource = try Self.sourceFiles(in: [
            "SumiTests",
        ]).filter { $0.relativePath.contains("ChromeMV3") }
        let runtimeJSBridgeScopedFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
        ]
        let allSource = chromeMV3Source + testSource
        let joined = allSource
            .filter { source in
                runtimeJSBridgeScopedFiles.contains {
                    source.relativePath.hasSuffix($0)
                } == false
            }
            .map(\.contents)
            .joined(separator: "\n")

        let loadCallFiles = chromeMV3Source
            .filter { $0.contents.contains(".lo" + "ad(") }
            .map(\.relativePath)
            .sorted()
        XCTAssertEqual(
            loadCallFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ControllerLoadOwner.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionPageHostHarness.swift",
            ]
        )
        let selectorFiles = allSource
            .filter {
                $0.contents.contains(
                    "load" + "ExtensionContext"
                )
            }
            .map(\.relativePath)
            .sorted()
        XCTAssertTrue(
            selectorFiles.allSatisfy {
                $0 == "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContextCreationGate.swift"
                    || $0 == "Sumi/Models/Extension/ChromeMV3/ChromeMV3ControllerLoadGate.swift"
            },
            selectorFiles.joined(separator: ", ")
        )

        for forbidden in [
            "WKUser" + "Script(",
            "add" + "UserScript",
            "add" + "ScriptMessageHandler",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "chrome" + "RuntimeAvailableNow\\s*[:=].*" + "tr" + "ue",
            "js" + "BridgeAvailableNow\\s*[:=].*" + "tr" + "ue",
            "canExecute" + "ExtensionCodeNow\\s*[:=].*" + "tr" + "ue",
            "service" + "WorkerWakeCount\\s*[:=].*" + "[1-9]",
            "native" + "MessagingPortCount\\s*[:=].*" + "[1-9]",
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

    @MainActor
    private func gateInput(
        rootURL: URL,
        profileIdentifier: String = UUID().uuidString,
        extensionsModuleEnabled: Bool = true,
        profileHostModuleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalControllerLoadProbeAllowed: Bool = true,
        acceptedWebExtensionObjectAvailable: Bool = true,
        objectProbeDiagnostics:
            ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport? = nil,
        detachedContextDiagnostics:
            ChromeMV3DetachedContextOwnerDiagnostics?? =
                .some(nil),
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics?? =
                .some(nil),
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport? = nil,
        sdkCompatibility: ChromeMV3ControllerLoadSDKCompatibility =
            .currentAppleSDK
    ) throws -> ChromeMV3ControllerLoadGateInput {
        let candidate = makeCandidate(rootURL: rootURL)
        let runtimeReport = makeRuntimeLoadabilityReport(rootPath: rootURL.path)
        let resolvedObjectReport = objectAcceptanceReport
            ?? makeObjectAcceptanceReport(
                rootURL: rootURL,
                accepted: acceptedWebExtensionObjectAvailable,
                runtimeReport: runtimeReport
            )
        let resolvedEmptyController: ChromeMV3EmptyControllerDiagnostics?
        switch emptyControllerDiagnostics {
        case .none:
            resolvedEmptyController = nil
        case .some(.none):
            resolvedEmptyController =
                try makeCreatedEmptyControllerOwner(
                    profileIdentifier: profileIdentifier
                ).diagnostics()
        case let .some(.some(diagnostics)):
            resolvedEmptyController = diagnostics
        }
        let resolvedDetached: ChromeMV3DetachedContextOwnerDiagnostics?
        switch detachedContextDiagnostics {
        case .none:
            resolvedDetached = nil
        case .some(.none):
            let contextGateDecision =
                try makeContextCreationDecision(
                    rootURL: rootURL,
                    profileIdentifier: profileIdentifier,
                    objectAcceptanceReport: resolvedObjectReport,
                    runtimeLoadabilityReport: runtimeReport,
                    emptyControllerDiagnostics:
                        resolvedEmptyController
                        ?? makeCreatedEmptyControllerOwner(
                            profileIdentifier: profileIdentifier
                        ).diagnostics()
                )
            resolvedDetached =
                ChromeMV3DetachedContextOwnerDiagnostics.make(
                    state: .createdDetached,
                    gateDecision: contextGateDecision,
                    contextObjectCreated: true
                )
        case let .some(.some(diagnostics)):
            resolvedDetached = diagnostics
        }
        let acceptedObjectAvailable =
            acceptedWebExtensionObjectAvailable
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            acceptedWebExtensionObjectAvailable: acceptedObjectAvailable,
            detachedContextCreated:
                resolvedDetached?.contextObjectCreated ?? false
        )
        let readiness: ChromeMV3RuntimeBridgeReadinessReport
        if let runtimeBridgeReadinessReport {
            readiness = runtimeBridgeReadinessReport
        } else {
            readiness = try makeRuntimeBridgeReadinessReport(
                rootURL: rootURL,
                runtimeLoadabilityReport: runtimeReport,
                objectAcceptanceReport: resolvedObjectReport,
                emptyControllerDiagnostics:
                    resolvedEmptyController
                    ?? makeCreatedEmptyControllerOwner(
                        profileIdentifier: profileIdentifier
                    ).diagnostics()
            )
        }

        return ChromeMV3ControllerLoadGateInput(
            candidateID: candidate.id,
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostModuleState: profileHostModuleState,
            profileIdentifier: profileIdentifier,
            explicitInternalControllerLoadProbeAllowed:
                explicitInternalControllerLoadProbeAllowed,
            acceptedWebExtensionObjectAvailable: acceptedObjectAvailable,
            objectProbeDiagnostics: objectProbeDiagnostics,
            objectAcceptanceReport: resolvedObjectReport,
            detachedContextOwnerDiagnostics: resolvedDetached,
            emptyControllerDiagnostics: resolvedEmptyController,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport: readiness,
            minimalInertFixturePolicy: minimalPolicy,
            sdkCompatibility: sdkCompatibility,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false
        )
    }

    @MainActor
    private func prepareAcceptedDetachedContext(rootURL: URL)
        async throws -> PreparedControllerLoadFixture
    {
        let runtimeReport = makeRuntimeLoadabilityReport(rootPath: rootURL.path)
        let candidate = makeCandidate(rootURL: rootURL)
        let objectDecision = ChromeMV3ExtensionObjectProbeGate.evaluate(
            input: objectProbeGateInput(
                rootURL: rootURL,
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
                "WKWebExtension object probe failed with active SDK: \(probeDiagnostics.error?.message ?? "unknown")"
            )
        }
        let objectReport =
            ChromeMV3WebKitObjectAcceptanceReportGenerator.makeReport(
                candidate: candidate,
                gateDecision: objectDecision,
                probeDiagnostics: probeDiagnostics,
                runtimeLoadabilityReport: runtimeReport
            )
        guard objectReport.objectAcceptedByWebKit else {
            throw XCTSkip("WKWebExtension object was not accepted.")
        }

        let emptyOwner = try makeCreatedEmptyControllerOwner()
        let readiness = try makeRuntimeBridgeReadinessReport(
            rootURL: rootURL,
            runtimeLoadabilityReport: runtimeReport,
            objectAcceptanceReport: objectReport,
            emptyControllerDiagnostics: emptyOwner.diagnostics()
        )
        let contextDecision = ChromeMV3ContextCreationGate.evaluate(
            input: ChromeMV3ContextCreationGateInput(
                candidateID: candidate.id,
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier:
                    emptyOwner.diagnostics().profileIdentifier,
                explicitInternalContextCreationAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: probeDiagnostics,
                objectAcceptanceReport: objectReport,
                emptyControllerDiagnostics: emptyOwner.diagnostics(),
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
        let accepted = try XCTUnwrap(
            probeOwner.acceptedWebExtensionObjectForDetachedContext(
                objectAcceptanceReport: objectReport
            )
        )
        let detachedOwner = ChromeMV3DetachedContextOwner(
            gateDecision: contextDecision
        )
        let contextDiagnostics = detachedOwner.createDetachedContextIfAllowed(
            acceptedWebExtension: accepted
        )
        guard contextDiagnostics.contextObjectCreated else {
            throw XCTSkip("Detached context was not created.")
        }

        return PreparedControllerLoadFixture(
            acceptedWebExtension: accepted,
            probeDiagnostics: probeDiagnostics,
            objectAcceptanceReport: objectReport,
            runtimeBridgeReadinessReport: readiness,
            emptyControllerOwner: emptyOwner,
            detachedContextOwner: detachedOwner,
            contextDiagnostics: contextDiagnostics
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
                        domain: "SumiTests.ControllerLoad",
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
    private func makeContextCreationDecision(
        rootURL: URL,
        profileIdentifier: String,
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport,
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics
    ) throws -> ChromeMV3ContextCreationGateDecision {
        ChromeMV3ContextCreationGate.evaluate(
            input: ChromeMV3ContextCreationGateInput(
                candidateID: makeCandidate(rootURL: rootURL).id,
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier: profileIdentifier,
                explicitInternalContextCreationAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: nil,
                objectAcceptanceReport: objectAcceptanceReport,
                emptyControllerDiagnostics: emptyControllerDiagnostics,
                liveNormalTabAttachmentSnapshot: nil,
                runtimeBridgeReadinessReport:
                    try makeRuntimeBridgeReadinessReport(
                        rootURL: rootURL,
                        runtimeLoadabilityReport: runtimeLoadabilityReport,
                        objectAcceptanceReport: objectAcceptanceReport,
                        emptyControllerDiagnostics:
                            emptyControllerDiagnostics
                    ),
                sdkCompatibility: .currentAppleSDK,
                requestedContextLoading: false,
                requestedControllerLoad: false,
                requestedExtensionCodeExecution: false,
                requestedUserScriptRegistration: false,
                requestedNativeMessagingLaunch: false
            )
        )
    }

    @MainActor
    private func makeCreatedEmptyControllerOwner(
        profileIdentifier: String = UUID().uuidString
    ) throws -> ChromeMV3EmptyControllerOwner {
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
                    .profileIdentifier(profileIdentifier),
                disabledRuntimeInvariantStatus: .satisfied
            )
        )
        return try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: decision,
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: identifier
            )
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
        let emptyController = try emptyControllerDiagnostics
            ?? makeCreatedEmptyControllerOwner().diagnostics()
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
            webExtensionContextCreated: true,
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
            id: "runtime-loadability-controller-load-test",
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
            runtimeLoadableFalseReason: "Controller load gate test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Controller Load",
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
        id: String = "controller-load-candidate"
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
        probe: ControllerLoadModuleProbe
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

@available(macOS 15.5, *)
private struct PreparedControllerLoadFixture {
    var acceptedWebExtension: WKWebExtension
    var probeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport
    var runtimeBridgeReadinessReport: ChromeMV3RuntimeBridgeReadinessReport
    var emptyControllerOwner: ChromeMV3EmptyControllerOwner
    var detachedContextOwner: ChromeMV3DetachedContextOwner
    var contextDiagnostics: ChromeMV3DetachedContextOwnerDiagnostics
}

@MainActor
private final class ControllerLoadModuleProbe {
    let profile = Profile(name: "Chrome MV3 Controller Load Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
