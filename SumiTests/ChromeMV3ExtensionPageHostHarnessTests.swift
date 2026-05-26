import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ExtensionPageHostHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDeclarationModelDetectsActionPopupAndOptionsPages()
        throws
    {
        let root = try makeExtensionPageRoot(
            named: "declarations",
            manifest: [
                "manifest_version": 3,
                "name": "Page Host Fixture",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
                "options_page": "options.html",
                "options_ui": ["page": "embedded.html"],
            ],
            resources: [
                "popup.html": pageHTML(title: "Popup"),
                "options.html": pageHTML(title: "Options"),
                "embedded.html": pageHTML(title: "Embedded"),
            ]
        )

        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )

        XCTAssertTrue(model.actionDefaultPopupDeclared)
        XCTAssertTrue(model.optionsPageDeclared)
        XCTAssertTrue(model.optionsUIPageDeclared)
        XCTAssertEqual(model.declarations.count, 3)
        XCTAssertEqual(
            model.declarations.map(\.sourceManifestField),
            ["action.default_popup", "options_page", "options_ui.page"]
        )
        XCTAssertTrue(model.declarations.allSatisfy(\.resourceExists))
        XCTAssertTrue(model.declarations.allSatisfy {
            $0.pathSafety == .safe
        })
    }

    func testResourceResolverRejectsUnsafePath() throws {
        let root = try makeExtensionPageRoot(
            named: "unsafe-path",
            manifest: [
                "manifest_version": 3,
                "name": "Unsafe Path",
                "version": "1.0",
                "action": ["default_popup": "../popup.html"],
            ],
            resources: [:]
        )

        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        let declaration = try XCTUnwrap(model.declarations.first)
        let resolution = ChromeMV3ExtensionPageResourceResolver.resolve(
            declaration: declaration
        )

        XCTAssertEqual(declaration.pathSafety, .unsafe)
        XCTAssertFalse(resolution.resourceSafeForExtensionPageHost)
        XCTAssertTrue(
            resolution.blockingReasons.contains {
                $0.contains("unsafe") || $0.contains("escapes")
            }
        )
    }

    func testMissingPageResourceIsDiagnosed() throws {
        let root = try makeExtensionPageRoot(
            named: "missing-page",
            manifest: [
                "manifest_version": 3,
                "name": "Missing Page",
                "version": "1.0",
                "options_page": "missing.html",
            ],
            resources: [:]
        )

        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        let policy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: model,
            selectedKind: .optionsPage
        )

        XCTAssertFalse(policy.fixturePagePolicyPassed)
        XCTAssertTrue(policy.blockers.contains(.missingPageResource))
        XCTAssertFalse(policy.resourceResolution?.htmlPageExists ?? true)
    }

    func testRemoteResourceDependencyBlocksFixturePolicy() throws {
        let root = try makeExtensionPageRoot(
            named: "remote-resource",
            manifest: [
                "manifest_version": 3,
                "name": "Remote Resource",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
            ],
            resources: [
                "popup.html": pageHTML(
                    title: "Popup",
                    body:
                        #"<img src="https://example.com/logo.png" alt="">"#
                ),
            ]
        )

        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        let policy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: model,
            selectedKind: .actionPopup
        )

        XCTAssertFalse(policy.fixturePagePolicyPassed)
        XCTAssertTrue(policy.blockers.contains(.remoteResourceDependency))
        XCTAssertEqual(
            policy.resourceResolution?.remoteResourceReferences,
            ["https://example.com/logo.png"]
        )
    }

    func testInertLocalScriptIsAllowedButDynamicScriptIsBlocked()
        throws
    {
        let inertRoot = try makeExtensionPageRoot(
            named: "inert-script",
            manifest: [
                "manifest_version": 3,
                "name": "Inert Script",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
            ],
            resources: [
                "popup.html": pageHTML(
                    title: "Popup",
                    body:
                        #"<script src="fixture.js" data-sumi-inert="true"></script>"#
                ),
                "fixture.js": "const marker = 'inert fixture';",
            ]
        )
        let inertModel = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: inertRoot.path
        )
        let inertPolicy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: inertModel,
            selectedKind: .actionPopup
        )

        XCTAssertTrue(inertPolicy.fixturePagePolicyPassed)
        XCTAssertEqual(
            inertPolicy.resourceResolution?.inertLocalScriptPaths,
            ["fixture.js"]
        )

        let dynamicRoot = try makeExtensionPageRoot(
            named: "dynamic-script",
            manifest: [
                "manifest_version": 3,
                "name": "Dynamic Script",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
            ],
            resources: [
                "popup.html": pageHTML(
                    title: "Popup",
                    body: #"<script src="fixture.js"></script>"#
                ),
                "fixture.js": "const marker = 'dynamic fixture';",
            ]
        )
        let dynamicModel = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: dynamicRoot.path
        )
        let dynamicPolicy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: dynamicModel,
            selectedKind: .actionPopup
        )

        XCTAssertFalse(dynamicPolicy.fixturePagePolicyPassed)
        XCTAssertTrue(dynamicPolicy.blockers.contains(.dynamicScriptDependency))
    }

    func testNativeMessagingAndServiceWorkerBlockFixturePolicy()
        throws
    {
        let root = try makeExtensionPageRoot(
            named: "native-and-worker",
            manifest: [
                "manifest_version": 3,
                "name": "Native Worker",
                "version": "1.0",
                "permissions": ["nativeMessaging"],
                "background": ["service_worker": "worker.js"],
                "options_ui": ["page": "options.html"],
            ],
            resources: [
                "options.html": pageHTML(title: "Options"),
                "worker.js": "",
            ]
        )

        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        let policy = ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: model,
            selectedKind: .optionsUI
        )

        XCTAssertFalse(policy.fixturePagePolicyPassed)
        XCTAssertTrue(policy.blockers.contains(.nativeMessagingDetected))
        XCTAssertTrue(policy.blockers.contains(.serviceWorkerWakeRequirement))
    }

    func testHostGateRequiresExplicitFlagAndSameControllerState()
        throws
    {
        let root = try makeExtensionPageRoot(
            named: "gate",
            manifest: [
                "manifest_version": 3,
                "name": "Gate",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
            ],
            resources: ["popup.html": pageHTML(title: "Popup")]
        )
        let policy = try fixturePolicy(root: root, kind: .actionPopup)

        let missingFlag = ChromeMV3ExtensionPageHostGate.evaluate(
            input: gateInput(
                root: root,
                policy: policy,
                explicitInternalExtensionPageHostAllowed: false
            )
        )
        XCTAssertFalse(missingFlag.canCreateExtensionPageHostNow)
        XCTAssertTrue(missingFlag.blockers.contains(.explicitHostFlagMissing))

        let missingSameController = ChromeMV3ExtensionPageHostGate.evaluate(
            input: gateInput(
                root: root,
                policy: policy,
                sameControllerConfigurationAvailable: false
            )
        )
        XCTAssertFalse(missingSameController.canCreateExtensionPageHostNow)
        XCTAssertTrue(
            missingSameController.blockers.contains(
                .sameControllerConfigurationUnavailable
            )
        )
    }

    func testContextLoadUnavailableCreatesDeterministicBlockedReport()
        throws
    {
        let root = try makeExtensionPageRoot(
            named: "context-load-blocked",
            manifest: [
                "manifest_version": 3,
                "name": "Context Blocked",
                "version": "1.0",
                "options_page": "options.html",
            ],
            resources: ["options.html": pageHTML(title: "Options")]
        )
        let policy = try fixturePolicy(root: root, kind: .optionsPage)
        let decision = ChromeMV3ExtensionPageHostGate.evaluate(
            input: gateInput(
                root: root,
                policy: policy,
                loadedContextAvailable: false,
                sameControllerConfigurationAvailable: false
            )
        )
        let report = ChromeMV3ExtensionPageHostReportGenerator.makeReport(
            candidateID: "context-load-blocked",
            generatedRewrittenRootPath: root.path,
            selectedKind: .optionsPage,
            declarationModel: policy.pageDeclarationSummary,
            fixturePolicy: policy,
            gateDecision: decision,
            syntheticConfigurationResult:
                ChromeMV3ExtensionPageHostReportGenerator
                .blockedConfigurationResult(
                    reasons: decision.blockingReasons
                ),
            syntheticWebViewResult:
                ChromeMV3ExtensionPageHostReportGenerator.webViewResult(
                    created: false,
                    sameController: false,
                    pageURL: .notAvailable,
                    loadState: .blocked,
                    navigationAttempted: false,
                    navigationErrorDescription: nil,
                    blockers: decision.blockingReasons,
                    warnings: []
                ),
            observationResult:
                ChromeMV3ExtensionPageHostReportGenerator.observationResult(
                    state: .blocked,
                    attempted: false,
                    diagnostics: decision.blockingReasons
                ),
            teardownResult:
                ChromeMV3ExtensionPageHostReportGenerator.teardownResult(
                    webViewCreated: false,
                    configurationCreated: false,
                    contextOwnerTeardownRequested: false,
                    controllerOwnerTeardownRequested: false
                )
        )

        XCTAssertEqual(report.outcome, .blocked)
        XCTAssertTrue(report.hostGateResult.blockers.contains(.contextLoadUnavailable))
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.productUIExposed)
        XCTAssertFalse(report.jsBridgeAvailableNow)
        XCTAssertEqual(report.sideEffectCounters.serviceWorkerWakeCount, 0)
        XCTAssertEqual(report.sideEffectCounters.runtimeDispatchCount, 0)
        XCTAssertEqual(report.sideEffectCounters.nativeMessagingPortCount, 0)
        XCTAssertEqual(report.sideEffectCounters.processLaunchCount, 0)
        XCTAssertEqual(report.sideEffectCounters.productUIExposureCount, 0)
    }

    @MainActor
    func testDisabledModuleBlocksExtensionPageHostAndWritesNoReport()
        async throws
    {
        guard #available(macOS 15.5, *) else { return }
        let root = try makeExtensionPageRoot(
            named: "disabled-module",
            manifest: [
                "manifest_version": 3,
                "name": "Disabled Module",
                "version": "1.0",
                "action": ["default_popup": "popup.html"],
            ],
            resources: ["popup.html": pageHTML(title: "Popup")]
        )
        let registry = makeRegistry(enabled: false)
        let module = try makeModule(registry: registry)
        let report = await module
            .chromeMV3RuntimeExtensionPageHostReportIfEnabled(
                selectedKind: .actionPopup,
                explicitInternalExtensionPageHostAllowed: true,
                explicitSyntheticWebViewCreationAllowed: true,
                explicitSyntheticNavigationAllowed: true,
                explicitTestDOMInspectionAllowed: true,
                candidate: candidate(root: root),
                writeReport: true
            )

        XCTAssertNil(report)
        XCTAssertFalse(module.hasLoadedRuntime)
        let reportURL = root.appendingPathComponent(
            ChromeMV3ExtensionPageHostReportWriter.reportFileName
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))
    }

    func testReportWriterIsDeterministicAndKeepsRuntimeDisabled()
        throws
    {
        let root = try makeExtensionPageRoot(
            named: "report-writer",
            manifest: [
                "manifest_version": 3,
                "name": "Report Writer",
                "version": "1.0",
                "options_ui": ["page": "options.html"],
            ],
            resources: ["options.html": pageHTML(title: "Options")]
        )
        let policy = try fixturePolicy(root: root, kind: .optionsUI)
        let decision = ChromeMV3ExtensionPageHostGate.evaluate(
            input: gateInput(root: root, policy: policy)
        )
        let report = ChromeMV3ExtensionPageHostReportGenerator.makeReport(
            candidateID: "report-writer",
            generatedRewrittenRootPath: root.path,
            selectedKind: .optionsUI,
            declarationModel: policy.pageDeclarationSummary,
            fixturePolicy: policy,
            gateDecision: decision,
            syntheticConfigurationResult:
                ChromeMV3ExtensionPageHostReportGenerator
                .blockedConfigurationResult(
                    reasons: decision.blockingReasons
                ),
            syntheticWebViewResult:
                ChromeMV3ExtensionPageHostReportGenerator.webViewResult(
                    created: false,
                    sameController: false,
                    pageURL: .notAvailable,
                    loadState: .blocked,
                    navigationAttempted: false,
                    navigationErrorDescription: nil,
                    blockers: decision.blockingReasons,
                    warnings: []
                ),
            observationResult:
                ChromeMV3ExtensionPageHostReportGenerator.observationResult(
                    state: .blocked,
                    attempted: false,
                    diagnostics: decision.blockingReasons
                ),
            teardownResult:
                ChromeMV3ExtensionPageHostReportGenerator.teardownResult(
                    webViewCreated: false,
                    configurationCreated: false,
                    contextOwnerTeardownRequested: false,
                    controllerOwnerTeardownRequested: false
                )
        )

        try ChromeMV3ExtensionPageHostReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let data = try Data(
            contentsOf:
                root.appendingPathComponent(
                    ChromeMV3ExtensionPageHostReportWriter.reportFileName
                )
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3ExtensionPageHostReport.self,
            from: data
        )

        XCTAssertEqual(decoded.id, report.id)
        XCTAssertFalse(decoded.runtimeLoadable)
        XCTAssertFalse(decoded.productUIExposed)
        XCTAssertFalse(decoded.summary.runtimeLoadable)
        XCTAssertFalse(decoded.summary.productUIExposed)
    }

    func testSourceLevelGuardsForExtensionPageHostHarness()
        throws
    {
        let sources = try sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let runtimeJSBridgeScopedFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
        ]
        let joined = sources
            .filter {
                runtimeJSBridgeScopedFiles.contains($0.relativePath) == false
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
            "Ti" + "mer",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable.*" + "tr" + "ue",
            "chromeRuntimeAvailableNow.*" + "tr" + "ue",
            "jsBridgeAvailableNow.*" + "tr" + "ue",
            "productUIExposed.*" + "tr" + "ue",
            "serviceWorkerWake" + "Count.*[1-9]",
            "runtimeDispatch" + "Count.*[1-9]",
            "nativeMessagingPort" + "Count.*[1-9]",
            "processLaunch" + "Count.*[1-9]",
        ] {
            let regex = try NSRegularExpression(pattern: forbiddenRegex)
            let range = NSRange(joined.startIndex..., in: joined)
            XCTAssertNil(
                regex.firstMatch(in: joined, range: range),
                forbiddenRegex
            )
        }

        let scopedJoined = sources
            .filter { runtimeJSBridgeScopedFiles.contains($0.relativePath) }
            .map(\.contents)
            .joined(separator: "\n")
        XCTAssertTrue(scopedJoined.contains("add" + "ScriptMessageHandler"))
        XCTAssertFalse(scopedJoined.contains("WKUser" + "Script("))
        XCTAssertFalse(scopedJoined.contains("connect" + "Native"))
        XCTAssertFalse(scopedJoined.contains("Pro" + "cess("))
    }

    private func fixturePolicy(
        root: URL,
        kind: ChromeMV3ExtensionPageKind
    ) throws -> ChromeMV3ExtensionPageFixturePolicyResult {
        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        return ChromeMV3ExtensionPageFixturePolicy.evaluate(
            declarationModel: model,
            selectedKind: kind
        )
    }

    private func gateInput(
        root: URL,
        policy: ChromeMV3ExtensionPageFixturePolicyResult,
        explicitInternalExtensionPageHostAllowed: Bool = true,
        loadedContextAvailable: Bool = true,
        sameControllerConfigurationAvailable: Bool = true
    ) -> ChromeMV3ExtensionPageHostGateInput {
        let loadDecision = controllerLoadDecision(
            root: root,
            loadedContextAvailable: loadedContextAvailable
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
        return ChromeMV3ExtensionPageHostGateInput(
            candidateID: "extension-page-host-test",
            generatedRewrittenRootPath: root.path,
            selectedKind: policy.selectedKind ?? .actionPopup,
            extensionsModuleEnabled: true,
            explicitInternalExtensionPageHostAllowed:
                explicitInternalExtensionPageHostAllowed,
            explicitSyntheticWebViewCreationAllowed: true,
            explicitSyntheticNavigationAllowed: true,
            explicitTestDOMInspectionAllowed: true,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextAvailable: true,
            controllerLoadGateDecision: loadDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            loadedContextAvailable: loadedContextAvailable,
            sameControllerConfigurationAvailable:
                sameControllerConfigurationAvailable,
            syntheticConfigurationUserScriptCount: 0,
            fixturePolicy: policy,
            runtimeBridgeReadinessReport: nil,
            liveNormalTabAttachmentSnapshot: nil,
            requestedProductUI: false,
            requestedToolbarIntegration: false,
            requestedSettingsIntegration: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedNativeMessagingLaunch: false
        )
    }

    private func controllerLoadDecision(
        root: URL,
        loadedContextAvailable: Bool
    ) -> ChromeMV3ControllerLoadGateDecision {
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: root.path,
            acceptedWebExtensionObjectAvailable: true,
            detachedContextCreated: true
        )
        let input = ChromeMV3ControllerLoadGateInput(
            candidateID: "extension-page-host-test",
            generatedRewrittenRootPath: root.path,
            extensionsModuleEnabled: true,
            profileHostModuleState: .enabled,
            profileIdentifier: "extension-page-host-profile",
            explicitInternalControllerLoadProbeAllowed: true,
            acceptedWebExtensionObjectAvailable: true,
            objectProbeDiagnostics: nil,
            objectAcceptanceReport: nil,
            detachedContextOwnerDiagnostics: nil,
            emptyControllerDiagnostics: nil,
            liveNormalTabAttachmentSnapshot: nil,
            runtimeBridgeReadinessReport: nil,
            minimalInertFixturePolicy: minimalPolicy,
            contentScriptSmokeFixturePolicy: nil,
            sdkCompatibility: .currentAppleSDK,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false
        )
        return ChromeMV3ControllerLoadGateDecision(
            input: input,
            canLoadContextIntoControllerNow: loadedContextAvailable,
            loadAttemptAllowed: loadedContextAvailable,
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
    }

    private func makeExtensionPageRoot(
        named name: String,
        manifest: [String: Any],
        resources: [String: String]
    ) throws -> URL {
        let root = try temporaryDirectory(named: name)
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys, .prettyPrinted]
        )
        try manifestData.write(
            to: root.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (path, contents) in resources {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func pageHTML(
        title: String,
        body: String = ""
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="content-security-policy" content="script-src 'self'; object-src 'self';">
        <title>\(title)</title>
        </head>
        <body data-sumi-extension-page-fixture-marker="\(title)">
        \(body)
        </body>
        </html>
        """
    }

    private func candidate(root: URL) -> ChromeMV3RewrittenVariantCandidate {
        ChromeMV3RewrittenVariantCandidate(
            id: root.lastPathComponent,
            generatedVariantRootPath: root.path,
            rewrittenVariantRootPath: root.path,
            runtimeLoadabilityReportPath: nil,
            manifestVersion: 3,
            rewrittenVariantExists: true
        )
    }

    @MainActor
    private func makeRegistry(enabled: Bool) -> SumiModuleRegistry {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3ExtensionPageHostHarnessTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return registry
    }

    @MainActor
    private func makeModule(
        registry: SumiModuleRegistry
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration()
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3ExtensionPageHostHarnessTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func sourceFiles(
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
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey]
                )
                guard values.isRegularFile == true else { continue }
                let relative = String(
                    file.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                results.append(
                    (
                        relative,
                        try String(contentsOf: file, encoding: .utf8)
                    )
                )
            }
        }
        return results
    }
}
