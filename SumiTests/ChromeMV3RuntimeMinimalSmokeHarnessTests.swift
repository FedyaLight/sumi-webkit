import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeMinimalSmokeHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksSmokeHarnessAndWritesNoReport() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 smoke harness requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "smoke-disabled")
        let candidate = makeCandidate(rootURL: root)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = SmokeModuleProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let report = module.chromeMV3RuntimeMinimalSmokeHarnessReportIfEnabled(
            explicitInternalSmokeHarnessAllowed: true,
            explicitSyntheticWebViewCreationAllowed: true,
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
                    ChromeMV3RuntimeMinimalSmokeReportWriter.reportFileName
                ).path
            )
        )
    }

    @MainActor
    func testSmokeGateBlocksMissingExplicitFlagNonMinimalFixtureLoadedContextAndSameController()
        throws
    {
        let root = try makeSimpleRewrittenRoot(named: "smoke-gate")
        let missingFlag = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(
                rootURL: root,
                explicitInternalSmokeHarnessAllowed: false
            )
        )
        let nonMinimalRoot = try makeSimpleRewrittenRoot(
            named: "smoke-non-minimal",
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
        let nonMinimal = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(rootURL: nonMinimalRoot)
        )
        let missingLoadedContext = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(
                rootURL: root,
                loadedContextAvailable: false
            )
        )
        let missingSameController = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(
                rootURL: root,
                sameControllerAvailable: false
            )
        )

        XCTAssertFalse(missingFlag.canRunSmokeHarnessNow)
        XCTAssertTrue(
            missingFlag.blockers.contains(.explicitSmokeHarnessNotAllowed)
        )
        XCTAssertFalse(nonMinimal.canRunSmokeHarnessNow)
        XCTAssertTrue(
            nonMinimal.blockers.contains(.minimalInertFixturePolicyFailed)
        )
        XCTAssertTrue(
            nonMinimal.input.minimalInertFixturePolicy.blockers
                .contains(.contentScriptsPresent)
        )
        XCTAssertFalse(missingLoadedContext.canRunSmokeHarnessNow)
        XCTAssertTrue(
            missingLoadedContext.blockers.contains(.loadedContextMissing)
        )
        XCTAssertFalse(missingSameController.canRunSmokeHarnessNow)
        XCTAssertTrue(
            missingSameController.blockers.contains(.sameControllerMissing)
        )
        for decision in [
            missingFlag,
            nonMinimal,
            missingLoadedContext,
            missingSameController,
        ] {
            XCTAssertFalse(decision.runtimeLoadable)
            XCTAssertFalse(decision.chromeRuntimeAvailableNow)
            XCTAssertFalse(decision.jsBridgeAvailableNow)
            XCTAssertFalse(decision.productRuntimeExposed)
            XCTAssertFalse(decision.canNavigateSyntheticWebViewNow)
        }
    }

    @MainActor
    func testSmokeReportWriterIsDeterministicAndProfileDiagnosticsCanCarryLatestReport()
        throws
    {
        let root = try makeSimpleRewrittenRoot(named: "smoke-report")
        let decision = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(rootURL: root)
        )
        let report = ChromeMV3RuntimeMinimalSmokeReportGenerator
            .makeBlockedReport(gateDecision: decision)
        try ChromeMV3RuntimeMinimalSmokeReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let firstData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3RuntimeMinimalSmokeReportWriter.reportFileName
            )
        )
        let second = ChromeMV3RuntimeMinimalSmokeReportGenerator
            .makeBlockedReport(gateDecision: decision)
        try ChromeMV3RuntimeMinimalSmokeReportWriter.write(
            second,
            toRewrittenBundleRoot: root
        )
        let secondData = try Data(
            contentsOf: root.appendingPathComponent(
                ChromeMV3RuntimeMinimalSmokeReportWriter.reportFileName
            )
        )

        XCTAssertEqual(report, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3RuntimeMinimalSmokeReportWriter.reportFileName
        )

        let host = ChromeMV3ProfileHost(
            profileIdentifier: "profile-smoke",
            extensionsEnabled: true,
            profileDataStoreIdentity: .profileIdentifier("profile-smoke"),
            candidateRewrittenVariants: [makeCandidate(rootURL: root)]
        )
        let diagnostics = host.diagnostics(
            runtimeMinimalSmokeReport: report
        )
        XCTAssertEqual(diagnostics.runtimeMinimalSmokeReport, report)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
    }

    @MainActor
    func testSameControllerSyntheticConfigurationSmokeKeepsRuntimeUnavailable()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 smoke harness requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "smoke-config")
        let prepared = try await prepareLoadedContext(rootURL: root)
        let report = ChromeMV3RuntimeMinimalSmokeHarness.run(
            candidate: makeCandidate(rootURL: root),
            extensionsModuleEnabled: true,
            explicitInternalSmokeHarnessAllowed: true,
            explicitSyntheticWebViewCreationAllowed: false,
            objectAcceptanceReport: prepared.objectAcceptanceReport,
            runtimeBridgeReadinessReport:
                prepared.runtimeBridgeReadinessReport,
            emptyControllerOwner: prepared.emptyControllerOwner,
            detachedContextOwner: prepared.detachedContextOwner,
            controllerLoadOwner: prepared.controllerLoadOwner,
            tearDownLoadedContextAndControllerAfterRun: true,
            diagnosticsResetForFutureRuns: true
        )

        XCTAssertEqual(report.outcome, .passed)
        XCTAssertTrue(report.gateDecision.canRunSmokeHarnessNow)
        XCTAssertTrue(
            report.sameControllerSyntheticConfigurationResult
                .syntheticConfigurationCreated
        )
        XCTAssertTrue(
            report.sameControllerSyntheticConfigurationResult
                .syntheticConfigurationAttached
        )
        XCTAssertTrue(
            report.sameControllerSyntheticConfigurationResult
                .controllerIdentityMatchesLoadedContextController
        )
        XCTAssertFalse(
            report.sameControllerSyntheticConfigurationResult
                .realNormalTabConfigurationTouched
        )
        XCTAssertTrue(
            report.sameControllerSyntheticConfigurationResult
                .helperPreviewMiniFaviconDownloadSurfacesExcluded
        )
        XCTAssertTrue(
            report.sameControllerSyntheticConfigurationResult
                .disabledDefaultPathsRemainUnattached
        )
        XCTAssertEqual(
            report.syntheticWebViewResult.state,
            .notRequested
        )
        XCTAssertFalse(report.syntheticWebViewResult.syntheticWebViewCreated)
        XCTAssertFalse(report.syntheticWebViewResult.navigationAttempted)
        assertRuntimeSideEffectsStayUnavailable(report)
        XCTAssertTrue(report.teardownResult.loadedContextOwnerTornDown)
        XCTAssertTrue(report.teardownResult.controllerOwnerTornDown)
        XCTAssertTrue(report.teardownResult.detachedContextReleased)
        XCTAssertFalse(
            report.teardownResult
                .syntheticConfigurationAttachedAfterTeardown
        )
        XCTAssertTrue(
            report.webKitInternalUncertaintyNotes.contains {
                $0.contains("unverified")
            }
        )
    }

    @MainActor
    func testOptionalSyntheticWebViewCreationUsesSameControllerWithoutNavigation()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 smoke harness requires macOS 15.5.")
        }

        let root = try makeSimpleRewrittenRoot(named: "smoke-webview")
        let prepared = try await prepareLoadedContext(rootURL: root)
        let report = ChromeMV3RuntimeMinimalSmokeHarness.run(
            candidate: makeCandidate(rootURL: root),
            extensionsModuleEnabled: true,
            explicitInternalSmokeHarnessAllowed: true,
            explicitSyntheticWebViewCreationAllowed: true,
            objectAcceptanceReport: prepared.objectAcceptanceReport,
            runtimeBridgeReadinessReport:
                prepared.runtimeBridgeReadinessReport,
            emptyControllerOwner: prepared.emptyControllerOwner,
            detachedContextOwner: prepared.detachedContextOwner,
            controllerLoadOwner: prepared.controllerLoadOwner,
            tearDownLoadedContextAndControllerAfterRun: true,
            diagnosticsResetForFutureRuns: true
        )

        XCTAssertEqual(report.outcome, .passed)
        XCTAssertEqual(report.syntheticWebViewResult.state, .created)
        XCTAssertTrue(report.syntheticWebViewResult.syntheticWebViewCreated)
        XCTAssertTrue(
            report.syntheticWebViewResult.syntheticWebViewUsesSameController
        )
        XCTAssertFalse(report.syntheticWebViewResult.userVisibleWindowCreated)
        XCTAssertFalse(report.syntheticWebViewResult.productTabRegistered)
        XCTAssertFalse(report.syntheticWebViewResult.navigationAttempted)
        XCTAssertFalse(report.syntheticWebViewResult.safeInertURLLoaded)
        XCTAssertEqual(
            report.sideEffectCounters.syntheticWebViewCreated,
            1
        )
        XCTAssertEqual(
            report.sideEffectCounters.syntheticNavigationAttempted,
            0
        )
        assertRuntimeSideEffectsStayUnavailable(report)
        XCTAssertTrue(report.teardownResult.syntheticWebViewReleased)
        XCTAssertTrue(report.teardownResult.syntheticConfigurationReleased)
        XCTAssertTrue(report.teardownResult.loadedContextOwnerTornDown)
    }

    @MainActor
    func testRealNormalTabAndExcludedSurfacesRemainUntouchedBySmokeGate()
        throws
    {
        let root = try makeSimpleRewrittenRoot(named: "smoke-surfaces")
        let decision = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: try smokeGateInput(rootURL: root)
        )
        let profile = Profile(name: "Chrome MV3 Smoke Surfaces")
        let browserConfiguration = BrowserConfiguration()
        let normalConfiguration =
            browserConfiguration.normalTabWebViewConfiguration(
                for: profile,
                url: URL(string: "https://example.com")
            )
        let normalDiagnostic =
            ChromeMV3WebViewConfigurationAttachmentGuard.inspect(
                configuration: normalConfiguration,
                siteID: "smoke.normal",
                surface: .normalTab
            )

        XCTAssertTrue(decision.canRunSmokeHarnessNow)
        XCTAssertFalse(decision.diagnostics.realNormalTabsTouchedByDefault)
        XCTAssertTrue(
            decision.diagnostics.excludedSurfaces.contains(.normalTab)
        )
        XCTAssertTrue(
            decision.diagnostics.excludedSurfaces.contains(.helperWebView)
        )
        XCTAssertTrue(
            decision.diagnostics.excludedSurfaces.contains(.miniWindow)
        )
        XCTAssertTrue(
            decision.diagnostics.excludedSurfaces.contains(.faviconDownload)
        )
        XCTAssertTrue(
            decision.diagnostics.excludedSurfaces.contains(.downloadHelper)
        )
        XCTAssertTrue(normalDiagnostic.isNormalTabConfiguration)
        XCTAssertFalse(normalDiagnostic.hasControllerAttachment)
        XCTAssertFalse(normalDiagnostic.attachmentAllowedNow)
        XCTAssertNil(normalConfiguration.webExtensionController)

        for surface in [
            BrowserConfigurationAuxiliarySurface.faviconDownload,
            .glance,
            .miniWindow,
            .extensionOptions,
        ] {
            let configuration =
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: surface
                )
            XCTAssertNil(configuration.webExtensionController)
        }
    }

    func testSourceGuardsForSmokeHarnessBoundary() throws {
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
        let joined = (chromeMV3Source + testSource)
            .filter { source in
                runtimeJSBridgeScopedFiles.contains {
                    source.relativePath.hasSuffix($0)
                } == false
            }
            .map(\.contents)
            .joined(separator: "\n")

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
            "product" + "RuntimeExposed\\s*[:=].*" + "tr" + "ue",
            "service" + "WorkerWakeCount\\s*[:=].*" + "[1-9]",
            "runtime" + "DispatchCount\\s*[:=].*" + "[1-9]",
            "native" + "MessagingPortCount\\s*[:=].*" + "[1-9]",
            "pro" + "cessLaunchCount\\s*[:=].*" + "[1-9]",
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

    private func assertRuntimeSideEffectsStayUnavailable(
        _ report: ChromeMV3RuntimeMinimalSmokeReport,
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
        XCTAssertFalse(
            report.sideEffectCounters.jsBridgeAvailableNow,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.sumiJSInjectionCount,
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
            report.sideEffectCounters.storageEventDispatchCount,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            report.sideEffectCounters.productUIExposureCount,
            0,
            file: file,
            line: line
        )
    }

    @MainActor
    private func smokeGateInput(
        rootURL: URL,
        extensionsModuleEnabled: Bool = true,
        explicitInternalSmokeHarnessAllowed: Bool = true,
        explicitSyntheticWebViewCreationAllowed: Bool = false,
        acceptedWebExtensionObjectAvailable: Bool = true,
        detachedContextAvailable: Bool = true,
        loadedContextAvailable: Bool = true,
        sameControllerAvailable: Bool = true
    ) throws -> ChromeMV3RuntimeMinimalSmokeGateInput {
        let candidate = makeCandidate(rootURL: rootURL)
        let loadDecision = try controllerLoadDecision(
            rootURL: rootURL,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextAvailable: detachedContextAvailable
        )
        let loadDiagnostics = ChromeMV3ControllerLoadOwnerDiagnostics.make(
            state: loadedContextAvailable ? .loadedIntoController : .notAttempted,
            gateDecision: loadDecision,
            controllerLoadAttempted: loadedContextAvailable,
            contextLoadedIntoController: loadedContextAvailable,
            controllerLoadCount: loadedContextAvailable ? 1 : 0
        )
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextCreated: detachedContextAvailable
        )

        return ChromeMV3RuntimeMinimalSmokeGateInput(
            scenario: ChromeMV3RuntimeMinimalSmokeScenario(
                scenarioID: "smoke-gate-test",
                fixtureID: "minimal-inert-fixture:\(candidate.id)",
                extensionID: candidate.id,
                profileID: loadDecision.input.profileIdentifier
            ),
            generatedRewrittenRootPath:
                rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalSmokeHarnessAllowed:
                explicitInternalSmokeHarnessAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            syntheticNavigationRequested: false,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextAvailable: detachedContextAvailable,
            loadedContextAvailable: loadedContextAvailable,
            sameControllerAvailable: sameControllerAvailable,
            minimalInertFixturePolicy: minimalPolicy,
            controllerLoadGateDecision: loadDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot: nil,
            runtimeBridgeReadinessReport:
                try runtimeBridgeReadinessReport(rootURL: rootURL),
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedStorageEventDispatch: false,
            requestedProductUI: false
        )
    }

    @MainActor
    private func prepareLoadedContext(rootURL: URL)
        async throws -> PreparedSmokeFixture
    {
        let runtimeReport = runtimeLoadabilityReport(rootPath: rootURL.path)
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
                "WKWebExtension object probe failed: \(probeDiagnostics.error?.message ?? "unknown")"
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

        let emptyOwner = try createdEmptyControllerOwner()
        let readiness = try runtimeBridgeReadinessReport(
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

        let loadDecision = ChromeMV3ControllerLoadGate.evaluate(
            input: try controllerLoadGateInput(
                rootURL: rootURL,
                objectProbeDiagnostics: probeDiagnostics,
                objectAcceptanceReport: objectReport,
                detachedContextDiagnostics: contextDiagnostics,
                emptyControllerDiagnostics: emptyOwner.diagnostics(),
                runtimeBridgeReadinessReport: readiness
            )
        )
        let loadOwner = ChromeMV3ControllerLoadOwner(
            gateDecision: loadDecision
        )
        let loadDiagnostics = loadOwner.loadContextIntoControllerIfAllowed(
            emptyControllerOwner: emptyOwner,
            detachedContextOwner: detachedOwner,
            acceptedWebExtension: accepted
        )
        guard loadDiagnostics.state == .loadedIntoController,
              loadDiagnostics.contextLoadedIntoController
        else {
            throw XCTSkip(
                "Inert context load did not complete: \(loadDiagnostics.webKitError?.message ?? loadDiagnostics.state.rawValue)"
            )
        }

        return PreparedSmokeFixture(
            objectAcceptanceReport: objectReport,
            runtimeBridgeReadinessReport: readiness,
            emptyControllerOwner: emptyOwner,
            detachedContextOwner: detachedOwner,
            controllerLoadOwner: loadOwner
        )
    }

    @MainActor
    private func controllerLoadDecision(
        rootURL: URL,
        acceptedWebExtensionObjectAvailable: Bool,
        detachedContextAvailable: Bool
    ) throws -> ChromeMV3ControllerLoadGateDecision {
        ChromeMV3ControllerLoadGate.evaluate(
            input: try controllerLoadGateInput(
                rootURL: rootURL,
                acceptedWebExtensionObjectAvailable:
                    acceptedWebExtensionObjectAvailable,
                detachedContextDiagnostics:
                    detachedContextAvailable ? nil : .make(
                        state: .notCreated,
                        gateDecision:
                            contextCreationDecision(
                                rootURL: rootURL,
                                objectAcceptanceReport:
                                    objectAcceptanceReport(
                                        rootURL: rootURL,
                                        accepted:
                                            acceptedWebExtensionObjectAvailable
                                    ),
                                emptyControllerDiagnostics:
                                    createdEmptyControllerOwner()
                                    .diagnostics()
                            ),
                        contextObjectCreated: false
                    )
            )
        )
    }

    @MainActor
    private func controllerLoadGateInput(
        rootURL: URL,
        acceptedWebExtensionObjectAvailable: Bool = true,
        objectProbeDiagnostics:
            ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport? = nil,
        detachedContextDiagnostics:
            ChromeMV3DetachedContextOwnerDiagnostics? = nil,
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics? = nil,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport? = nil
    ) throws -> ChromeMV3ControllerLoadGateInput {
        let runtimeReport = runtimeLoadabilityReport(rootPath: rootURL.path)
        let objectReport = objectAcceptanceReport
            ?? self.objectAcceptanceReport(
                rootURL: rootURL,
                accepted: acceptedWebExtensionObjectAvailable,
                runtimeReport: runtimeReport
            )
        let emptyDiagnostics = try emptyControllerDiagnostics
            ?? createdEmptyControllerOwner().diagnostics()
        let detachedDiagnostics = try detachedContextDiagnostics
            ?? ChromeMV3DetachedContextOwnerDiagnostics.make(
                state: .createdDetached,
                gateDecision:
                    contextCreationDecision(
                        rootURL: rootURL,
                        objectAcceptanceReport: objectReport,
                        emptyControllerDiagnostics: emptyDiagnostics
                    ),
                contextObjectCreated: true
            )
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextCreated:
                detachedDiagnostics.contextObjectCreated
        )

        return ChromeMV3ControllerLoadGateInput(
            candidateID: makeCandidate(rootURL: rootURL).id,
            generatedRewrittenRootPath: rootURL.standardizedFileURL.path,
            extensionsModuleEnabled: true,
            profileHostModuleState: .enabled,
            profileIdentifier: emptyDiagnostics.profileIdentifier,
            explicitInternalControllerLoadProbeAllowed: true,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            objectProbeDiagnostics: objectProbeDiagnostics,
            objectAcceptanceReport: objectReport,
            detachedContextOwnerDiagnostics: detachedDiagnostics,
            emptyControllerDiagnostics: emptyDiagnostics,
            liveNormalTabAttachmentSnapshot: nil,
            runtimeBridgeReadinessReport:
                try runtimeBridgeReadinessReport
                    ?? self.runtimeBridgeReadinessReport(
                        rootURL: rootURL,
                        runtimeLoadabilityReport: runtimeReport,
                        objectAcceptanceReport: objectReport,
                        emptyControllerDiagnostics: emptyDiagnostics
                    ),
            minimalInertFixturePolicy: minimalPolicy,
            sdkCompatibility: .currentAppleSDK,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false
        )
    }

    @MainActor
    private func contextCreationDecision(
        rootURL: URL,
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport,
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics
    ) throws -> ChromeMV3ContextCreationGateDecision {
        ChromeMV3ContextCreationGate.evaluate(
            input: ChromeMV3ContextCreationGateInput(
                candidateID: makeCandidate(rootURL: rootURL).id,
                generatedRewrittenRootPath:
                    rootURL.standardizedFileURL.path,
                extensionsModuleEnabled: true,
                profileHostModuleState: .enabled,
                profileIdentifier:
                    emptyControllerDiagnostics.profileIdentifier,
                explicitInternalContextCreationAllowed: true,
                acceptedWebExtensionObjectAvailable: true,
                objectProbeDiagnostics: nil,
                objectAcceptanceReport: objectAcceptanceReport,
                emptyControllerDiagnostics: emptyControllerDiagnostics,
                liveNormalTabAttachmentSnapshot: nil,
                runtimeBridgeReadinessReport:
                    try runtimeBridgeReadinessReport(
                        rootURL: rootURL,
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
    private func createdEmptyControllerOwner(
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
    private func runtimeBridgeReadinessReport(
        rootURL: URL,
        runtimeLoadabilityReport:
            ChromeMV3RuntimeLoadabilityReport? = nil,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport? = nil,
        emptyControllerDiagnostics:
            ChromeMV3EmptyControllerDiagnostics? = nil
    ) throws -> ChromeMV3RuntimeBridgeReadinessReport {
        let runtimeReport = runtimeLoadabilityReport
            ?? self.runtimeLoadabilityReport(rootPath: rootURL.path)
        let objectReport = objectAcceptanceReport
            ?? self.objectAcceptanceReport(
                rootURL: rootURL,
                accepted: true,
                runtimeReport: runtimeReport
            )
        let emptyController = try emptyControllerDiagnostics
            ?? createdEmptyControllerOwner().diagnostics()
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

    private func objectAcceptanceReport(
        rootURL: URL,
        accepted: Bool,
        runtimeReport: ChromeMV3RuntimeLoadabilityReport? = nil
    ) -> ChromeMV3WebKitObjectAcceptanceReport {
        let candidate = makeCandidate(rootURL: rootURL)
        let runtimeReport = runtimeReport
            ?? runtimeLoadabilityReport(rootPath: rootURL.path)
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
                        domain: "SumiTests.RuntimeMinimalSmoke",
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

    private func runtimeLoadabilityReport(
        rootPath: String
    ) -> ChromeMV3RuntimeLoadabilityReport {
        ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-smoke-test",
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
            runtimeLoadableFalseReason: "Smoke harness test report.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    private func makeSimpleRewrittenRoot(
        named name: String,
        manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Smoke",
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
        id: String = "runtime-minimal-smoke-candidate"
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
        probe: SmokeModuleProbe
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
private struct PreparedSmokeFixture {
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport
    var runtimeBridgeReadinessReport: ChromeMV3RuntimeBridgeReadinessReport
    var emptyControllerOwner: ChromeMV3EmptyControllerOwner
    var detachedContextOwner: ChromeMV3DetachedContextOwner
    var controllerLoadOwner: ChromeMV3ControllerLoadOwner
}

@MainActor
private final class SmokeModuleProbe {
    let profile = Profile(name: "Chrome MV3 Runtime Minimal Smoke Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
