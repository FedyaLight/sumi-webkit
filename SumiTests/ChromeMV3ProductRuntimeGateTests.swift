import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ProductRuntimeGateTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_710_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDefaultProductRuntimeGateIsBlockedOff() throws {
        let fixture = try makeInstalledFixture(
            named: "default-gate",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.defaultBlocked(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )

        XCTAssertEqual(gateSet.globalProductRuntimeGate.state, .blocked)
        XCTAssertEqual(gateSet.profileProductRuntimeGate.state, .notConfigured)
        XCTAssertEqual(gateSet.extensionProductRuntimeGate.state, .internalOnly)
        XCTAssertEqual(gateSet.tabProductRuntimeGate.state, .notConfigured)
        XCTAssertEqual(gateSet.diagnosticsGate.state, .internalOnly)
        XCTAssertEqual(gateSet.debugOverrideGate.state, .disabled)
        XCTAssertFalse(gateSet.allExplicitGatesAllowPreflight)
        XCTAssertTrue(gateSet.records.allSatisfy {
            $0.productFlagImpact.allSatisfy { $0.impact == .remainsFalse }
        })
    }

    func testExtensionProductEnablementDefaultsToInternalOnlyWithBlockers()
        throws
    {
        let fixture = try makeInstalledFixture(
            named: "default-extension",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.defaultBlocked(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )

        let enablement = ChromeMV3ExtensionProductEnablementEvaluator.evaluate(
            report: fixture.report,
            lifecycleRecord: fixture.record,
            gateSet: gateSet
        )

        XCTAssertEqual(enablement.state, .internalOnly)
        XCTAssertFalse(enablement.canEverAttachToProductNormalTab)
        XCTAssertFalse(enablement.productBlockerIDs.isEmpty)
        XCTAssertFalse(enablement.requiresProductAPIsStillBlocked)
    }

    func testNormalTabPreflightBlocksWithoutGlobalGate() throws {
        let fixture = try makeInstalledFixture(
            named: "global-blocked",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.defaultBlocked(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            sameControllerRequirementSatisfied: true
        )

        XCTAssertFalse(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(preflight.blockers.contains {
            $0.kind == .gateBlocked
                && $0.source == .defaultOffPolicy
        })
        XCTAssertFalse(preflight.canExposeRuntimeBridgeNow)
    }

    func testNormalTabPreflightBlocksWithoutExtensionGate() throws {
        let fixture = try makeInstalledFixture(
            named: "extension-gate-blocked",
            manifest: minimalNoBackgroundManifest()
        )
        var gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        gateSet.extensionProductRuntimeGate = .make(
            .extensionProductRuntimeGate,
            state: .internalOnly,
            reason: "Focused test leaves extension product gate internal-only.",
            blockerIDs: gateSet.extensionProductRuntimeGate.blockerIDs,
            source: .extensionProductRuntimeGate,
            productFlagImpact: .remainsFalse
        )

        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            sameControllerRequirementSatisfied: true
        )

        XCTAssertFalse(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(preflight.blockers.contains {
            $0.kind == .gateBlocked
                && $0.source == .extensionProductRuntimeGate
        })
        XCTAssertEqual(preflight.extensionEnablement.state, .internalOnly)
    }

    func testNormalTabPreflightBlocksWithoutTabGate() throws {
        let fixture = try makeInstalledFixture(
            named: "tab-gate-blocked",
            manifest: minimalNoBackgroundManifest()
        )
        var gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        gateSet.tabProductRuntimeGate = .make(
            .tabProductRuntimeGate,
            state: .notConfigured,
            reason: "Focused test leaves tab product gate unconfigured.",
            source: .tabProductRuntimeGate,
            productFlagImpact: .remainsFalse
        )

        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            sameControllerRequirementSatisfied: true
        )

        XCTAssertFalse(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(preflight.blockers.contains {
            $0.kind == .gateBlocked
                && $0.source == .tabProductRuntimeGate
        })
    }

    func testNormalTabPreflightBlocksWhenGeneratedBundleMissing() throws {
        let fixture = try makeInstalledFixture(
            named: "missing-bundle",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        let input = ChromeMV3ProductNormalTabRuntimePreflightInput.make(
            report: fixture.report,
            lifecycleRecord: fixture.record,
            gateSet: gateSet,
            generatedBundleActive: false,
            generatedBundleExists: false,
            sameControllerRequirementSatisfied: true
        )
        let preflight =
            ChromeMV3ProductNormalTabRuntimePreflightEvaluator.evaluate(
                input: input
            )

        XCTAssertFalse(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(preflight.blockers.contains {
            $0.kind == .generatedBundleMissing
        })
    }

    func testNormalTabPreflightBlocksProductAPIsStillBlocked() throws {
        let fixture = try makeInstalledFixture(
            named: "product-api-blockers",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            sameControllerRequirementSatisfied: true
        )
        let blockerKinds = Set(preflight.blockers.map(\.kind))

        XCTAssertFalse(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(
            blockerKinds.isSuperset(of: [
                .contentScriptProductPolicyBlocked,
                .nativeMessagingProductPolicyBlocked,
                .permissionProductPolicyBlocked,
                .productNetworkEnforcementBlocked,
                .serviceWorkerProductPolicyBlocked,
                .sidePanelOffscreenIdentityProductPolicyBlocked,
            ])
        )
        XCTAssertTrue(preflight.extensionEnablement.requiresProductAPIsStillBlocked)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canUseNativeMessagingNow)
        XCTAssertFalse(preflight.canUseProductNetworkEnforcementNow)
    }

    func testExplicitInternalProductGateFixtureCanPrepareMinimalNormalTabPath()
        throws
    {
        let fixture = try makeInstalledFixture(
            named: "allowed-minimal",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record,
            tabID: "fixture-tab"
        )
        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            tabID: "fixture-tab",
            sameControllerRequirementSatisfied: true
        )

        XCTAssertEqual(preflight.extensionEnablement.state, .productTestEnabled)
        XCTAssertTrue(preflight.canAttachToNormalTabNow)
        XCTAssertTrue(preflight.canExposeRuntimeBridgeNow)
        XCTAssertFalse(preflight.canInjectContentScriptsNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canUseNativeMessagingNow)
        XCTAssertFalse(preflight.canUseProductNetworkEnforcementNow)
        XCTAssertFalse(preflight.waivedCompatibilityBlockerIDs.isEmpty)
        XCTAssertTrue(preflight.blockers.isEmpty)
    }

    func testProductBridgeAttachmentPlanIsDeterministicAndPlanOnly()
        throws
    {
        let fixture = try makeInstalledFixture(
            named: "plan",
            manifest: minimalNoBackgroundManifest()
        )
        let gateSet = ChromeMV3ProductRuntimeGateSet.explicitInternalTestAllowed(
            report: fixture.report,
            lifecycleRecord: fixture.record
        )
        let preflight = evaluatePreflight(
            fixture: fixture,
            gateSet: gateSet,
            sameControllerRequirementSatisfied: true
        )

        let first = ChromeMV3ProductBridgeAttachmentPlan.make(
            preflight: preflight,
            report: fixture.report
        )
        let second = ChromeMV3ProductBridgeAttachmentPlan.make(
            preflight: preflight,
            report: fixture.report
        )

        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedString(first),
            try ChromeMV3DeterministicJSON.encodedString(second)
        )
        XCTAssertTrue(first.planOnly)
        XCTAssertFalse(first.performsAttachmentNow)
        XCTAssertTrue(first.canPrepareAttachmentNow)
        XCTAssertTrue(first.wouldAttachWKWebViewConfigurationWebExtensionController)
        XCTAssertEqual(first.plannedJSBridgeNamespaces, ["chrome.runtime"])
        XCTAssertEqual(first.exposedJSBridgeNamespacesNow, ["chrome.runtime"])
        XCTAssertFalse(first.wouldWakeServiceWorkerNow)
        XCTAssertFalse(first.wouldUseNativeMessagingNow)
        XCTAssertFalse(first.wouldUseProductNetworkEnforcementNow)
    }

    @MainActor
    func testDisabledModuleCreatesNoProductGateRuntimeState() throws {
        let root = try temporaryDirectory()
        let module = try makeModule(enabled: false)

        XCTAssertNil(
            module.chromeMV3ProductEnablementPreflightIfEnabled(
                rootURL: root,
                profileID: "profile-disabled",
                extensionID: "extension-disabled"
            )
        )
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("lifecycle").path
            )
        )
    }

    @MainActor
    func testNoProductBrowserConfigAttachmentOrJSShimByDefault() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Product Gate Default Off")

        let result = browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: profile,
                url: URL(string: "https://example.com")
            )
        let plainConfiguration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )

        XCTAssertTrue(result.configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(
            result.configuration
                .sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertEqual(
            result.configuration.userContentController.userScripts.count,
            plainConfiguration.userContentController.userScripts.count
        )
        XCTAssertEqual(result.diagnostics.userScriptRegistrationCount, 0)
        XCTAssertFalse(result.diagnostics.nativeMessagingLaunched)
        XCTAssertEqual(result.diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(result.diagnostics.runtimeLoadable)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
    }

    func testProductGateSourceGuardsKeepRuntimeOffAndNoScheduling()
        throws
    {
        let productSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductRuntimeGate.swift"
        )
        let diagnosticsSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3CompatibilityDiagnostics.swift"
        )
        let moduleSource = try source(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        for token in ["Ti" + "mer", "DispatchSource" + "Ti" + "mer"] {
            XCTAssertFalse(productSource.contains(token), token)
        }
        XCTAssertFalse(productSource.contains("Process" + "("))
        XCTAssertFalse(productSource.contains("addUser" + "Script"))
        XCTAssertFalse(productSource.contains("addScript" + "MessageHandler"))
        try assertProductFlagsNeverEnabled(
            sources: [productSource, diagnosticsSource, moduleSource]
        )
    }

    func testCompatibilityReportIncludesProductEnablementPreflight()
        throws
    {
        let fixture = try makeInstalledFixture(
            named: "compat-report-product-preflight",
            manifest: blockerHeavyManifest(),
            files: [
                "background.js": "",
                "content.js": "",
                "panel.html": "<!doctype html><title>Panel</title>\n",
                "rules.json": "[]",
            ]
        )
        let viewModel = try XCTUnwrap(
            fixture.registry.compatibilityReportViewModel(
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        let section = viewModel.productEnablementPreflight

        XCTAssertEqual(
            section.gateSummary.globalProductRuntimeGate.state,
            .blocked
        )
        XCTAssertEqual(
            section.extensionProductEnablement.state,
            .internalOnly
        )
        XCTAssertFalse(section.normalTabPreflight.canAttachToNormalTabNow)
        XCTAssertFalse(section.bridgeAttachmentPlan.performsAttachmentNow)
        XCTAssertFalse(section.productBlockerIDs.isEmpty)
        XCTAssertTrue(section.nextPhaseBlockers.contains {
            $0.contains("Product DNR/network enforcement policy")
        })
    }

    func testFoundationReadinessReportIncludesProductEnablementPreflight()
        throws
    {
        let fixture = try makeInstalledFixture(
            named: "foundation-product-preflight",
            manifest: minimalNoBackgroundManifest()
        )
        let foundation = try XCTUnwrap(
            fixture.registry.writeFoundationReadinessReport(
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        let section = try XCTUnwrap(foundation.productEnablementPreflight)

        XCTAssertFalse(foundation.finalPhaseStatus.productRuntimeAvailable)
        XCTAssertFalse(foundation.finalPhaseStatus.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(foundation.finalPhaseStatus.runtimeLoadable)
        XCTAssertEqual(section.gateSummary.globalProductRuntimeGate.state, .blocked)
        XCTAssertFalse(section.normalTabPreflight.canExposeRuntimeBridgeNow)
    }

    private func evaluatePreflight(
        fixture: InstalledFixture,
        gateSet: ChromeMV3ProductRuntimeGateSet,
        tabID: String = "normal-tab-preflight",
        sameControllerRequirementSatisfied: Bool
    ) -> ChromeMV3ProductNormalTabRuntimePreflight {
        let input = ChromeMV3ProductNormalTabRuntimePreflightInput.make(
            report: fixture.report,
            lifecycleRecord: fixture.record,
            gateSet: gateSet,
            tabID: tabID,
            sameControllerRequirementSatisfied:
                sameControllerRequirementSatisfied
        )
        return ChromeMV3ProductNormalTabRuntimePreflightEvaluator.evaluate(
            input: input
        )
    }

    private func makeInstalledFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String] = [:]
    ) throws -> InstalledFixture {
        let root = try temporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let registry = ChromeMV3ExtensionLifecycleRegistry(
            rootURL: root,
            now: { self.fixedDate }
        )
        let install = registry.installUnpackedExtension(
            at: source,
            profileID: "profile-\(name)",
            runtimeDiagnostics: fullRuntimeDiagnostics()
        )
        let record = try XCTUnwrap(install.record)
        let report = try XCTUnwrap(
            registry.latestEndToEndDiagnosticsReport(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        )
        return InstalledFixture(
            registry: registry,
            record: record,
            report: report
        )
    }

    private func fullRuntimeDiagnostics()
        -> ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
    {
        ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
            WebKitObjectDiagnosticsAvailable: true,
            contextCreationGateDiagnosticsAvailable: true,
            controllerLoadGateDiagnosticsAvailable: true,
            runtimeBridgeReadinessDiagnosticsAvailable: true,
            runtimeJSMessagingDiagnosticsAvailable: true,
            tabsScriptingDiagnosticsAvailable: true,
            permissionsDiagnosticsAvailable: true,
            storageDiagnosticsAvailable: true,
            nativeMessagingDiagnosticsAvailable: true,
            serviceWorkerDiagnosticsAvailable: true,
            eventAPIDiagnosticsAvailable: true,
            networkDiagnosticsAvailable: true,
            sidePanelOffscreenIdentityDiagnosticsAvailable: true,
            passwordManagerDiagnosticsAvailable: true,
            diagnostics: [
                "Focused product-gate test supplied all internal diagnostics.",
            ]
        )
    }

    private func minimalNoBackgroundManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Product Gate Minimal",
            "version": "1.0.0",
        ]
    }

    private func blockerHeavyManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Product Gate Blocker Heavy",
            "version": "1.0.0",
            "permissions": [
                "declarativeNetRequest",
                "webRequest",
                "webRequestBlocking",
                "sidePanel",
                "offscreen",
                "identity",
                "nativeMessaging",
                "storage",
            ],
            "host_permissions": ["https://example.com/*"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "rules_1",
                        "enabled": true,
                        "path": "rules.json",
                    ],
                ],
            ],
            "side_panel": [
                "default_path": "panel.html",
            ],
            "oauth2": [
                "client_id": "fixture",
                "scopes": ["email"],
            ],
            "action": [
                "default_popup": "panel.html",
            ],
        ]
    }

    private func makeFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try temporaryDirectory()
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

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return SumiExtensionsModule(moduleRegistry: registry)
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

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func assertProductFlagsNeverEnabled(sources: [String]) throws {
        let enabledWord = "tr" + "ue"
        let patterns = [
            "productRuntimeAvailable.*\(enabledWord)",
            "normalTabRuntimeBridgeAvailable.*\(enabledWord)",
            "runtimeLoadable.*\(enabledWord)",
            "productExtensionUIAvailable.*\(enabledWord)",
            "productNetworkEnforcementAvailable.*\(enabledWord)",
            "productRuntimeExposed.*\(enabledWord)",
        ]
        for source in sources {
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..., in: source)
                XCTAssertEqual(
                    regex.numberOfMatches(in: source, range: range),
                    0,
                    pattern
                )
            }
        }
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct InstalledFixture {
    var registry: ChromeMV3ExtensionLifecycleRegistry
    var record: ChromeMV3ExtensionLifecycleRecord
    var report: ChromeMV3EndToEndInstallDiagnosticsReport
}
