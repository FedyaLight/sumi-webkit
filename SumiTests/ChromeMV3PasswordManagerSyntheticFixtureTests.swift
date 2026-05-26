import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3PasswordManagerSyntheticFixtureTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksPasswordManagerFixtureReportAndWritesNoFile()
        throws
    {
        guard #available(macOS 15.5, *) else { throw XCTSkip("Requires macOS 15.5 WebKit API surface") }
        let root = try temporaryDirectory(named: "disabled-module")
        let module = try makeModule(enabled: false)

        let report = module.chromeMV3PasswordManagerFixtureReportIfEnabled(
            fromRewrittenBundleRoot: root,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(
                        ChromeMV3PasswordManagerFixtureReportWriter
                            .reportFileName
                    )
                    .path
            )
        )
        XCTAssertFalse(module.tearDownChromeMV3PasswordManagerFixtureIfEnabled())
    }

    func testFixtureManifestCatalogIsDeterministicAndClassifiesBlockers() {
        let first = ChromeMV3PasswordManagerFixtureManifestCatalog.all(
            extensionID: "fixture-extension"
        )
        let second = ChromeMV3PasswordManagerFixtureManifestCatalog.all(
            extensionID: "fixture-extension"
        )
        let native = ChromeMV3PasswordManagerFixtureManifestCatalog.fixture(
            variant: .nativeMessagingRequired,
            extensionID: "fixture-extension"
        )
        let serviceWorker =
            ChromeMV3PasswordManagerFixtureManifestCatalog.fixture(
                variant: .serviceWorkerRequired,
                extensionID: "fixture-extension"
            )
        let activeTab = ChromeMV3PasswordManagerFixtureManifestCatalog.fixture(
            variant: .activeTab,
            extensionID: "fixture-extension"
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, ChromeMV3PasswordManagerFixtureVariant.allCases.count)
        XCTAssertTrue(first.allSatisfy { manifest in
            object(manifest.manifestValue)?["manifest_version"] == .number(3)
        })
        XCTAssertTrue(native.nativeMessagingRequired)
        XCTAssertEqual(native.expectedReadinessClassification, .partial)
        XCTAssertEqual(native.facts.nativeHostName, "com.sumi.synthetic_password_manager")
        XCTAssertTrue(serviceWorker.serviceWorkerRequired)
        XCTAssertEqual(serviceWorker.expectedReadinessClassification, .blocked)
        XCTAssertTrue(activeTab.hostPermissionRequirements.contains("temporary activeTab grant for example.com"))
        XCTAssertFalse(activeTab.nativeMessagingRequired)
        XCTAssertFalse(activeTab.serviceWorkerRequired)
    }

    func testLoginPageFixtureIsSyntheticAndFillPayloadDeterministic() {
        let login = ChromeMV3PasswordManagerLoginPageFixture.exampleLogin
        let detected = object(login.detectedFieldMetadata)
        let command = object(login.fillCommandPayload)
        let result = object(login.fillResultPayload)

        XCTAssertEqual(login.url, "https://example.com/login")
        XCTAssertEqual(login.origin, "https://example.com")
        XCTAssertFalse(login.iframePresent)
        XCTAssertEqual(object(detected?["username"])?["selector"], .string("#username"))
        XCTAssertEqual(object(detected?["password"])?["type"], .string("password"))
        XCTAssertEqual(command?["type"], .string("fillFields"))
        XCTAssertEqual(object(command?["credential"])?["passwordRef"], .string("synthetic-password-token"))
        XCTAssertEqual(result?["success"], .bool(true))
        XCTAssertTrue(login.blockedUnsupportedCases.contains("real credential storage is not used"))
    }

    func testModelReportCoversIntegratedFlowsAndExplicitBlockers() {
        let report = ChromeMV3PasswordManagerFixtureReportGenerator
            .makeReport()

        XCTAssertTrue(report.passwordManagerSyntheticJSReady)
        XCTAssertFalse(report.passwordManagerNativeMessagingReady)
        XCTAssertFalse(report.passwordManagerServiceWorkerReady)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.productRuntimeExposed)

        XCTAssertTrue(report.storageFlowResult.setSucceeded)
        XCTAssertTrue(report.storageFlowResult.readBackSucceeded)
        XCTAssertTrue(report.storageFlowResult.removeSucceeded)
        XCTAssertTrue(report.storageFlowResult.onChangedObservedOrPayloadGenerated)
        XCTAssertTrue(report.tabDiscoveryResult.redactedWithoutPermission)
        XCTAssertTrue(report.tabDiscoveryResult.visibleWithActiveTab)
        XCTAssertTrue(report.tabDiscoveryResult.redactedAfterActiveTabExpiry)
        XCTAssertTrue(report.tabDiscoveryResult.visibleWithHostPermission)
        XCTAssertTrue(report.contentMessagingResult.detectFieldsSucceeded)
        XCTAssertTrue(report.contentMessagingResult.fillFieldsSucceeded)
        XCTAssertTrue(
            report.contentMessagingResult.noReceivingEndDeterministic,
            report.contentMessagingResult.diagnostics.joined(separator: " ")
        )
        XCTAssertTrue(report.contentMessagingResult.missingPermissionDeterministic)
        XCTAssertTrue(report.scriptingResult.executeScriptSucceededInControlledSyntheticTarget)
        XCTAssertTrue(report.scriptingResult.missingScriptingPermissionBlocks)
        XCTAssertTrue(report.scriptingResult.productTargetBlocks)
        XCTAssertTrue(report.permissionActiveTabResult.modeledAcceptGrantsOptionalHost)
        XCTAssertTrue(
            report.permissionActiveTabResult
                .requestWithoutModeledPromptReturnsProductUIUnavailable
        )
        XCTAssertEqual(
            report.nativeMessagingBlocker.nextBlockerPrompt,
            "Native messaging fixture implementation required"
        )
        XCTAssertFalse(report.nativeMessagingBlocker.canConnectNativeNow)
        XCTAssertFalse(report.nativeMessagingBlocker.processLaunchAllowedNow)
        XCTAssertEqual(report.serviceWorkerLifecycleBlocker.nextBlockerPrompt, "Prompt 51")
        XCTAssertFalse(report.serviceWorkerLifecycleBlocker.serviceWorkerWakeAvailable)
        XCTAssertFalse(report.serviceWorkerLifecycleBlocker.portKeepaliveProductReady)

        let readinessByAPI = Dictionary(
            uniqueKeysWithValues: report.apiReadinessMatrix.map {
                ($0.api, $0)
            }
        )
        XCTAssertEqual(readinessByAPI["runtime"]?.classification, .ready)
        XCTAssertEqual(readinessByAPI["tabs"]?.classification, .ready)
        XCTAssertEqual(readinessByAPI["scripting"]?.classification, .partial)
        XCTAssertEqual(readinessByAPI["permissions"]?.classification, .ready)
        XCTAssertEqual(readinessByAPI["activeTab"]?.classification, .ready)
        XCTAssertEqual(readinessByAPI["storage.local"]?.classification, .ready)
        XCTAssertEqual(readinessByAPI["nativeMessaging"]?.classification, .blocked)
        XCTAssertEqual(readinessByAPI["serviceWorkerLifecycle"]?.classification, .blocked)
    }

    func testNativeMessagingImplementationSummaryMakesFixtureInternallyReady()
        throws
    {
        let root = try temporaryDirectory(named: "native-fixture-ready")
        let nativeReport =
            try ChromeMV3NativeMessagingImplementationReportGenerator
            .makeReport(
                extensionID: "abcdefghijklmnopabcdefghijklmnop",
                profileID: "password-manager-native-profile",
                fixtureHostRootURL: root
            )

        let report = ChromeMV3PasswordManagerFixtureReportGenerator
            .makeReport(
                extensionID: "abcdefghijklmnopabcdefghijklmnop",
                profileID: "password-manager-native-profile",
                nativeMessagingImplementationSummary: nativeReport.summary
            )
        let readinessByAPI = Dictionary(
            uniqueKeysWithValues: report.apiReadinessMatrix.map {
                ($0.api, $0)
            }
        )

        XCTAssertTrue(report.passwordManagerNativeMessagingReady)
        XCTAssertTrue(report.passwordManagerNativeMessagingReadyInFixture)
        XCTAssertTrue(report.nativeMessagingBlocker.canConnectNativeNow)
        XCTAssertTrue(report.nativeMessagingBlocker.processLaunchAllowedNow)
        XCTAssertTrue(
            report.nativeMessagingBlocker
                .nativeMessagingAvailableInInternalFixture
        )
        XCTAssertTrue(
            report.nativeMessagingBlocker
                .processLaunchAllowedForFixtureHost
        )
        XCTAssertFalse(report.nativeMessagingBlocker.nativeMessagingAvailableInProduct)
        XCTAssertFalse(report.nativeMessagingBlocker.processLaunchAllowedInProduct)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertEqual(report.nativeMessagingBlocker.nextBlockerPrompt, "Prompt 51")
        XCTAssertEqual(readinessByAPI["nativeMessaging"]?.classification, .partial)
        XCTAssertEqual(
            report.nativeMessagingImplementationSummary,
            nativeReport.summary
        )
    }

    func testCombinedShimSourceLoadsOnlyControlledNamespacesAndProductFlagsStayFalse() {
        let configuration =
            ChromeMV3PasswordManagerCombinedHarnessConfiguration
            .syntheticHarness()
        let source = ChromeMV3PasswordManagerCombinedJSShimSource.source(
            configuration: configuration
        )
        let coverage = ChromeMV3PasswordManagerCombinedJSShimSource.coverage

        XCTAssertEqual(coverage.exposedChromeNamespaces, [
            "permissions",
            "runtime",
            "scripting",
            "storage",
            "tabs",
        ])
        XCTAssertEqual(coverage.storageAreas, ["local"])
        XCTAssertEqual(coverage.scriptingMethods, ["executeScript"])
        XCTAssertTrue(coverage.callbackModeSupported)
        XCTAssertTrue(coverage.promiseModeSupported)
        XCTAssertTrue(coverage.lastErrorScopedToCallbackTurn)
        XCTAssertTrue(source.contains("Object.defineProperty(globalThis, \"chrome\""))
        XCTAssertTrue(source.contains("__sumiChromeMV3PasswordManagerFixture"))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"nativeMessaging\""))
        XCTAssertFalse(configuration.passwordManagerProductRuntimeReady)
        XCTAssertFalse(configuration.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(configuration.runtimeLoadable)
    }

    @MainActor
    func testModuleReportWritesDeterministicCompatibilityReport() throws {
        guard #available(macOS 15.5, *) else { throw XCTSkip("Requires macOS 15.5 WebKit API surface") }
        let root = try temporaryDirectory(named: "module-report")
        let module = try makeModule(enabled: true)

        let report = try XCTUnwrap(
            module.chromeMV3PasswordManagerFixtureReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3PasswordManagerFixtureReportWriter.reportFileName
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3PasswordManagerFixtureReport.self,
            from: Data(contentsOf: reportURL)
        )

        XCTAssertEqual(decoded, report)
        XCTAssertTrue(report.passwordManagerSyntheticJSReady)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertTrue(module.tearDownChromeMV3PasswordManagerFixtureIfEnabled())
    }

    @MainActor
    func testWebKitCombinedHarnessRunsEndToEndAndTeardownClearsState()
        async throws
    {
        guard #available(macOS 15.5, *) else { throw XCTSkip("Requires macOS 15.5 WebKit API surface") }

        let result =
            await ChromeMV3PasswordManagerCombinedSyntheticHarness.run(
                scriptBody:
                    ChromeMV3PasswordManagerCombinedSyntheticHarness
                    .reportVerificationScriptBody
            )

        XCTAssertTrue(
            result.scriptEvaluationSucceeded,
            result.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(result.webKitExecutionSummary.storageFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.tabDiscoveryFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.contentMessagingFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.scriptingFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.permissionActiveTabFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.runtimeMessagingFlowPassed)
        XCTAssertTrue(result.webKitExecutionSummary.storageOnChangedObserved)
        XCTAssertEqual(result.userScriptCount, 1)
        XCTAssertEqual(result.scriptMessageHandlerCount, 4)
        XCTAssertTrue(result.syntheticWebViewCreated)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.runtimeLoadable)
        XCTAssertGreaterThan(result.handledRuntimeRequestCount, 0)
        XCTAssertGreaterThan(result.handledTabsRequestCount, 0)
        XCTAssertGreaterThan(result.handledStorageRequestCount, 0)
        XCTAssertGreaterThan(result.handledFixtureRequestCount, 0)
        XCTAssertEqual(result.tabRegistrySummaryAfterTeardown.controlledSyntheticTabCount, 0)
        XCTAssertEqual(result.storageStateSummaryAfterTeardown.keyCount, 0)
        XCTAssertTrue(result.report.passwordManagerSyntheticJSReady)
        XCTAssertFalse(result.report.passwordManagerProductRuntimeReady)
    }

    @MainActor
    func testModuleCombinedHarnessRespectsEnabledGate() async throws {
        guard #available(macOS 15.5, *) else { throw XCTSkip("Requires macOS 15.5 WebKit API surface") }
        let root = try temporaryDirectory(named: "module-combined-harness")
        let disabled = try makeModule(enabled: false)
        let enabled = try makeModule(enabled: true)

        let blocked =
            await disabled
            .chromeMV3PasswordManagerCombinedSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        let report = await enabled
            .chromeMV3PasswordManagerCombinedSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(blocked)
        XCTAssertNotNil(report)
        XCTAssertTrue(report?.webKitExecutionSummary.combinedJSExecutedInWebKitSyntheticHarness == true)
        XCTAssertEqual(report?.runtimeLoadable, false)
    }

    func testSourceGuardsKeepFixtureInternalAndNonProduct() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixturePath =
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
        let modulePath = "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        let browserConfigPath = "Sumi/Models/BrowserConfig/BrowserConfig.swift"
        let fixtureSource = try String(
            contentsOf: root.appendingPathComponent(fixturePath),
            encoding: .utf8
        )
        let moduleSource = try String(
            contentsOf: root.appendingPathComponent(modulePath),
            encoding: .utf8
        )
        let browserConfigSource = try String(
            contentsOf: root.appendingPathComponent(browserConfigPath),
            encoding: .utf8
        )

        for forbidden in [
            "Process" + "(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer" + "(",
            "runtime" + "Loadable" + ": " + "tr" + "ue",
            "passwordManagerProductRuntimeReady" + ": " + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable" + ": " + "tr" + "ue",
            "serviceWorkerWakeAvailable" + ": " + "tr" + "ue",
            "nativeMessagingAvailable" + ": " + "tr" + "ue",
            "processLaunchAllowedNow" + ": " + "tr" + "ue",
            "productRuntimeExposed" + ": " + "tr" + "ue",
        ] {
            XCTAssertFalse(fixtureSource.contains(forbidden), forbidden)
            XCTAssertFalse(moduleSource.contains(forbidden), forbidden)
        }

        XCTAssertFalse(
            browserConfigSource.contains(
                ChromeMV3PasswordManagerCombinedJSShimSource
                    .fixtureBridgeMessageHandlerName
            )
        )
        XCTAssertFalse(browserConfigSource.contains("__sumiChromeMV3PasswordManagerFixture"))
        XCTAssertTrue(fixtureSource.contains("sumiIsNormalTabWebViewConfiguration = false"))
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3PasswordManagerSyntheticFixtureTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
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
                "ChromeMV3PasswordManagerSyntheticFixtureTests",
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

    private func object(_ value: ChromeMV3StorageValue?)
        -> [String: ChromeMV3StorageValue]?
    {
        guard case .object(let object) = value else { return nil }
        return object
    }
}
