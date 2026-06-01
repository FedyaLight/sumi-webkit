import Foundation
import SwiftData
import XCTest
import zlib

@testable import Sumi

final class ChromeMV3PasswordManagerRealPackageCompatibilityTests:
    XCTestCase
{
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testExplicitLocalTargetCatalogUsesOnlyProvidedRootsAndDetectionWorks()
        throws
    {
        let targets =
            ChromeMV3PasswordManagerRealPackageTargetCatalog
            .explicitLocalTargets()
        let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.targetID, $0) })

        XCTAssertEqual(
            byID["bitwarden-real-local"]?.explicitAllowedLocalRoot,
            "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden"
        )
        XCTAssertEqual(
            byID["proton-pass-real-local"]?.explicitAllowedLocalRoot,
            "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/proton"
        )
        XCTAssertEqual(
            byID["onepassword-real-local"]?.explicitAllowedLocalRoot,
            "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/1password"
        )
        XCTAssertTrue(targets.allSatisfy(\.noRealCredentialsInvariant))
        XCTAssertTrue(targets.allSatisfy {
            $0.trustedFixtureHostRootPath?.hasPrefix(
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/native-host-fixtures/"
            ) == true
                && $0.expectedExtensionID == nil
        })

        let detections = targets.map {
            ChromeMV3PasswordManagerRealPackageDetector.detect(target: $0)
        }
        XCTAssertEqual(detections.count, 3)
        XCTAssertTrue(detections.allSatisfy {
            $0.explicitAllowedLocalRoot
                .hasPrefix("/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/")
        })
        for detection in detections {
            if FileManager.default.fileExists(
                atPath: detection.explicitAllowedLocalRoot
            ) {
                XCTAssertEqual(
                    detection.detectedPackageKind,
                    .unpackedExtensionRoot
                )
                XCTAssertTrue(
                    detection.sourceAvailability
                        .contains(.realPackageAvailable)
                )
                XCTAssertEqual(detection.manifestCandidatePaths, ["manifest.json"])
            } else {
                XCTAssertEqual(detection.detectedPackageKind, .missing)
                XCTAssertTrue(
                    detection.sourceAvailability
                        .contains(.skippedMissingPackage)
                )
            }
        }
    }

    func testBitwardenRealPackageWebpackChunkCandidateIsStaticallyBounded()
        throws
    {
        let workerURL = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden/background.js"
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: workerURL.path),
            "Bitwarden real package fixture is not available."
        )

        let source = try String(contentsOf: workerURL, encoding: .utf8)
        let candidates = staticallyBoundedImportScriptsCandidatesServiceWorkerJS(
            in: source
        )

        XCTAssertTrue(
            candidates.contains("719.background.js"),
            "Bounded candidates: \(candidates)"
        )
    }

    func testMissingRealPackageMarksSkippedAndUsesFixtureFallback()
        throws
    {
        let root = try temporaryDirectory(named: "missing-real-package")
        let missing = root.appendingPathComponent(
            "missing-bitwarden",
            isDirectory: true
        )
        let target = testTarget(
            id: "missing-bitwarden",
            targetClass: .bitwarden,
            root: missing
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [target],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 10) }
        )
        let config = try XCTUnwrap(report.targetConfigurations.first)
        let row = try XCTUnwrap(report.rows.first)

        XCTAssertEqual(config.detectedPackageKind, .missing)
        XCTAssertTrue(config.sourceAvailability.contains(.skippedMissingPackage))
        XCTAssertTrue(config.sourceAvailability.contains(.fixtureFallbackUsed))
        XCTAssertEqual(row.packageSource, .fixtureFallback)
        XCTAssertEqual(row.intake, .fixtureOnly)
        XCTAssertTrue(row.packageBlockers.contains {
            $0.contains("missing")
        })
        XCTAssertTrue(report.noWebStoreInstallAttempted)
        XCTAssertTrue(report.noRemoteCRXDownloadAttempted)
        XCTAssertFalse(report.arbitraryNativeHostDiscoveryAttempted)
        XCTAssertFalse(report.realVendorNativeHostLaunchAttempted)
    }

    func testLocalUnpackedTargetImportsAndExtractsManifest() throws {
        let root = try temporaryDirectory(named: "unpacked-real-package")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Bitwarden Local")
        )
        let target = testTarget(
            id: "bitwarden-local",
            targetClass: .bitwarden,
            root: package
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [target],
            writeReport: true,
            now: { Date(timeIntervalSince1970: 11) }
        )
        let row = try XCTUnwrap(report.rows.first)
        let decoded = try decodeReport(
            root.appendingPathComponent(
                ChromeMV3PasswordManagerRealPackageCompatibilityReport
                    .reportFileName
            )
        )

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(row.packageSource, .realLocalUnpacked)
        XCTAssertEqual(row.detectedPackageKind, .unpackedExtensionRoot)
        XCTAssertEqual(row.intake, .pass)
        XCTAssertEqual(row.manifest, .pass)
        XCTAssertEqual(row.generatedBundle, .pass)
        XCTAssertEqual(row.manifestRequirements.manifestVersion, 3)
        XCTAssertEqual(row.manifestRequirements.name, "Bitwarden Local")
        XCTAssertTrue(row.manifestRequirements.permissions.contains("storage"))
        XCTAssertTrue(row.serviceWorkerEventReadiness.declared)
        XCTAssertEqual(
            row.serviceWorkerEventReadiness
                .declarationReadiness?.backgroundServiceWorkerPath,
            "background.js"
        )
        XCTAssertEqual(
            row.serviceWorkerEventReadiness
                .declarationReadiness?.localExperimentalGateState,
            .runtimeGateBlocked
        )
        XCTAssertEqual(
            row.serviceWorkerEventReadiness
                .declarationReadiness?.runtimeLoadable,
            false
        )
        XCTAssertTrue(
            row.serviceWorkerEventReadiness.blockers.contains(
                "serviceWorker.runtimeLoadableFalse"
            )
        )
        XCTAssertFalse(
            row.serviceWorkerEventReadiness.jsExecutionPolicy
                .serviceWorkerJSExecutionAvailableInLocalExperimentalGate
        )
        XCTAssertTrue(
            row.serviceWorkerEventReadiness
                .actualListenerRegistrationCaptureStatus
                .contains("notAttempted")
        )
        XCTAssertEqual(
            row.serviceWorkerEventReadiness.trialGateRecords.map(\.state),
            [.blockedDefault]
        )
        XCTAssertEqual(
            row.serviceWorkerEventReadiness.staticVsExecutionDelta.status,
            .noListener
        )
        XCTAssertTrue(row.serviceWorkerEventReadiness.gateClosedAfterTrial)
        XCTAssertTrue(
            row.serviceWorkerEventReadiness.capturedListenerFamilies.isEmpty
        )
        XCTAssertTrue(
            row.serviceWorkerEventReadiness.actualDispatchResults.isEmpty
        )
        XCTAssertEqual(
            row.serviceWorkerEventReadiness.popupOptionsRuntimeMessage,
            .blocked
        )
        XCTAssertFalse(report.productRuntimeAvailable)
        XCTAssertFalse(report.productRuntimeExposed)
    }

    func testExplicitScopedServiceWorkerTrialCapturesDispatchesAndClosesGate()
        throws
    {
        let root = try temporaryDirectory(named: "scoped-service-worker-trial")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Bitwarden Trial"),
            extraFiles: [
                "background.js": """
                chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
                  sendResponse({ echoed: message.value });
                });
                chrome.runtime.onConnect.addListener((port) => {
                  port.onMessage.addListener((message) => port.postMessage(message));
                  port.onDisconnect.addListener(() => {});
                });
                chrome.storage.onChanged.addListener(() => {});
                chrome.permissions.onAdded.addListener(() => {});
                chrome.permissions.onRemoved.addListener(() => {});
                chrome.alarms.onAlarm.addListener(() => {});
                chrome.contextMenus.onClicked.addListener(() => {});
                chrome.webNavigation.onCommitted.addListener(() => {});
                """,
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "bitwarden-scoped-trial",
                    targetClass: .bitwarden,
                    root: package
                ),
            ],
            serviceWorkerTrialGateSource: .explicitTestTrial,
            writeReport: false,
            now: { Date(timeIntervalSince1970: 11.5) }
        )
        let readiness = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
        )

        XCTAssertEqual(
            readiness.trialGateRecords.map(\.state),
            [.blockedDefault, .openScopedTrial, .closedAfterTrial]
        )
        XCTAssertEqual(readiness.executionStartResult?.status, .running)
        XCTAssertEqual(
            readiness.staticVsExecutionDelta.status,
            .executionCaptured
        )
        XCTAssertTrue(
            readiness.capturedListenerFamilies.contains(.runtimeOnMessage)
        )
        XCTAssertTrue(
            readiness.capturedListenerFamilies.contains(.runtimeOnConnect)
        )
        XCTAssertTrue(
            readiness.actualDispatchResults.contains {
                $0.source == .popupOptionsRuntimeMessage
                    && $0.resultKind == .delivered
            }
        )
        XCTAssertTrue(readiness.runtimePortSmoke.attempted)
        XCTAssertTrue(readiness.runtimePortSmoke.portMessageDelivered)
        XCTAssertTrue(readiness.runtimePortSmoke.portDisconnected)
        XCTAssertTrue(readiness.runtimePortSmoke.keepaliveReleased)
        XCTAssertTrue(readiness.idleTeardownResult.contains("verified"))
        XCTAssertTrue(readiness.hardTimeoutTeardownResult.contains("verified"))
        XCTAssertTrue(readiness.gateClosedAfterTrial)
        XCTAssertFalse(readiness.jsExecutionPolicy.permanentBackgroundAvailable)
        XCTAssertFalse(readiness.jsExecutionPolicy.serviceWorkerJSExecutionAvailableByDefault)
        XCTAssertTrue(readiness.jsExecutionPolicy.timersAvailableInLocalExperimentalGate)
        XCTAssertFalse(readiness.jsExecutionPolicy.timersAvailableByDefault)
        XCTAssertFalse(readiness.jsExecutionPolicy.wallClockTimersAllowed)
        XCTAssertTrue(readiness.timerShimResult.hasPrefix("drained:"))
    }

    func testExplicitScopedServiceWorkerTrialImportsClassicDependenciesAndBlocksModule()
        throws
    {
        let root = try temporaryDirectory(named: "blocked-worker-resources")
        let modulePackage = root.appendingPathComponent(
            "onepassword",
            isDirectory: true
        )
        var moduleManifest = minimalManifest(name: "1Password Module")
        moduleManifest["background"] = [
            "service_worker": "background.js",
            "type": "module",
        ]
        try writePackage(at: modulePackage, manifest: moduleManifest)
        let importPackage = root.appendingPathComponent(
            "bitwarden",
            isDirectory: true
        )
        try writePackage(
            at: importPackage,
            manifest: minimalManifest(name: "Bitwarden ImportScripts"),
            extraFiles: [
                "background.js": "importScripts('dependency.js');\n",
                "dependency.js":
                    "chrome.runtime.onMessage.addListener(() => 'imported');",
            ]
        )
        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "onepassword-module",
                    targetClass: .onePassword,
                    root: modulePackage
                ),
                testTarget(
                    id: "bitwarden-importscripts",
                    targetClass: .bitwarden,
                    root: importPackage
                ),
            ],
            serviceWorkerTrialGateSource: .explicitTestTrial,
            writeReport: false,
            now: { Date(timeIntervalSince1970: 11.75) }
        )
        let byID = Dictionary(
            uniqueKeysWithValues: report.rows.map { ($0.targetID, $0) }
        )
        let module = try XCTUnwrap(
            byID["onepassword-module"]?.serviceWorkerEventReadiness
        )
        let imported = try XCTUnwrap(
            byID["bitwarden-importscripts"]?.serviceWorkerEventReadiness
        )

        XCTAssertTrue(
            module.resourceLoadResult?.blockers.contains(
                .moduleWorkerUnsupported
            ) == true
        )
        XCTAssertEqual(module.staticVsExecutionDelta.status, .executionBlocked)
        XCTAssertFalse(
            imported.resourceLoadResult?.blockers.contains(
                .importScriptsUnsupported
            ) == true
        )
        XCTAssertEqual(imported.importScriptsResolvedCount, 1)
        XCTAssertEqual(imported.importedScriptPaths, ["dependency.js"])
        XCTAssertEqual(imported.executionStartResult?.status, .running)
        XCTAssertTrue(
            imported.capturedListenerFamilies.contains(.runtimeOnMessage)
        )
        XCTAssertTrue(
            imported.actualDispatchResults.contains {
                $0.source == .popupOptionsRuntimeMessage
                    && $0.resultKind == .delivered
            }
        )
        XCTAssertTrue(imported.importScriptsResult.hasPrefix("resolved: 1"))
        XCTAssertTrue(
            module.moduleWorkerReadinessResult.contains(
                "sourceTextModuleLoaderUnavailable"
            )
        )
        XCTAssertTrue(
            imported.moduleWorkerReadinessResult.hasPrefix("notRequired:")
        )
        XCTAssertTrue(
            imported.dynamicImportRewriteResult.hasPrefix("notRequired:")
        )
        XCTAssertTrue(imported.dispatchSmokeResult.hasPrefix("attempted:"))
        XCTAssertEqual(
            imported.nextBlockerClassification,
            .dispatchDelivered
        )
        XCTAssertTrue(
            imported.staticVsExecutionDelta.unsupportedListenerForms.contains(
                "importScriptsUnsupported"
            ) == false
        )
        XCTAssertTrue(module.gateClosedAfterTrial)
        XCTAssertTrue(imported.gateClosedAfterTrial)
    }

    func testScopedServiceWorkerTrialReportsPreciseDynamicImportBlocker()
        throws
    {
        let root = try temporaryDirectory(named: "dynamic-import-real-package")
        let package = root.appendingPathComponent(
            "bitwarden-dynamic",
            isDirectory: true
        )
        var manifest = minimalManifest(name: "Bitwarden Dynamic Import")
        manifest["web_accessible_resources"] = [
            [
                "resources": ["dependency.js"],
                "matches": ["https://example.com/*"],
            ],
        ]
        try writePackage(
            at: package,
            manifest: manifest,
            extraFiles: [
                "background.js": """
                import('./dependency.js').then(() => {
                  chrome.runtime.onMessage.addListener(() => globalThis.dynamicDependencyValue);
                });
                """,
                "dependency.js":
                    "globalThis.dynamicDependencyValue = 'dependency';",
            ]
        )
        let blockedDefaultReport = ChromeMV3PasswordManagerRealPackageTrialRunner
            .run(
                rootURL: root.appendingPathComponent(
                    "blocked-default",
                    isDirectory: true
                ),
                targets: [
                    testTarget(
                        id: "bitwarden-dynamic-import-default",
                        targetClass: .bitwarden,
                        root: package
                    ),
                ],
                writeReport: false,
                now: { Date(timeIntervalSince1970: 11.8) }
            )
        let blockedDefaultReadiness = try XCTUnwrap(
            blockedDefaultReport.rows.first?.serviceWorkerEventReadiness
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "bitwarden-dynamic-import",
                    targetClass: .bitwarden,
                    root: package
                ),
            ],
            serviceWorkerTrialGateSource: .explicitTestTrial,
            writeReport: false,
            now: { Date(timeIntervalSince1970: 11.875) }
        )
        let readiness = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
        )

        XCTAssertNil(blockedDefaultReadiness.executionStartResult)
        XCTAssertEqual(
            blockedDefaultReadiness.trialGateRecords.map(\.state),
            [.blockedDefault]
        )
        XCTAssertFalse(
            blockedDefaultReadiness.jsExecutionPolicy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertEqual(
            blockedDefaultReadiness.dynamicImportRewriteResult,
            "notAttempted: service-worker resource loading was not reached."
        )
        XCTAssertEqual(readiness.executionStartResult?.status, .running)
        XCTAssertTrue(
            readiness.resourceLoadResult?.dynamicImportDetected == true
        )
        XCTAssertTrue(
            readiness.resourceLoadResult?
                .dynamicImportRewriteExperimentApplied == true
        )
        XCTAssertEqual(
            readiness.resourceLoadResult?.dynamicImportRewriteEvaluationCount,
            1
        )
        XCTAssertEqual(readiness.dynamicImportBlockers, [])
        XCTAssertTrue(
            readiness.capturedListenerFamilies.contains(.runtimeOnMessage)
        )
        XCTAssertEqual(readiness.staticVsExecutionDelta.status, .executionCaptured)
        XCTAssertTrue(
            readiness.actualDispatchResults.contains {
                $0.source == .popupOptionsRuntimeMessage
                    && $0.resultKind == .delivered
            }
        )
        XCTAssertTrue(readiness.importScriptsResult.hasPrefix("notRequired:"))
        XCTAssertTrue(readiness.dynamicImportRewriteResult.hasPrefix("applied:"))
        XCTAssertTrue(readiness.dispatchSmokeResult.hasPrefix("attempted:"))
        XCTAssertEqual(
            readiness.nextBlockerClassification,
            .dispatchDelivered
        )
        XCTAssertFalse(
            readiness.resourceLoadResult?
                .dynamicImportRewriteGeneratedBundleArtifactsMutated == true
        )
        XCTAssertTrue(readiness.gateClosedAfterTrial)
        XCTAssertFalse(readiness.jsExecutionPolicy.dynamicImportAvailable)
        XCTAssertTrue(
            readiness.jsExecutionPolicy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(readiness.jsExecutionPolicy.moduleWorkerImportAvailable)
    }

    func testLocalZIPTargetImportsThroughSafeZIPIntake() throws {
        let root = try temporaryDirectory(named: "zip-real-package")
        let allowed = root.appendingPathComponent("proton", isDirectory: true)
        try FileManager.default.createDirectory(
            at: allowed,
            withIntermediateDirectories: true
        )
        let zip = allowed.appendingPathComponent("proton-local.zip")
        try makeZIPData(entries: [
            ZIPFixtureEntry(
                path: "extension/manifest.json",
                data: try manifestData(minimalManifest(name: "Proton ZIP"))
            ),
            ZIPFixtureEntry(path: "extension/background.js", data: Data()),
            ZIPFixtureEntry(path: "extension/popup.html", data: Data()),
            ZIPFixtureEntry(path: "extension/content.js", data: Data()),
        ]).write(to: zip, options: [.atomic])
        let target = testTarget(
            id: "proton-zip",
            targetClass: .protonPass,
            root: allowed
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [target],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 12) }
        )
        let row = try XCTUnwrap(report.rows.first)

        XCTAssertEqual(row.detectedPackageKind, .directoryContainingLocalZip)
        XCTAssertEqual(row.packageSource, .realLocalZip)
        XCTAssertEqual(row.intake, .pass)
        XCTAssertEqual(row.manifest, .pass)
        XCTAssertEqual(row.generatedBundle, .pass)
    }

    func testAmbiguousInvalidAndCRXOnlyPackagesFallbackDeterministically()
        throws
    {
        let root = try temporaryDirectory(named: "blocked-package-shapes")
        let ambiguous = root.appendingPathComponent("ambiguous", isDirectory: true)
        try writePackage(
            at: ambiguous.appendingPathComponent("one", isDirectory: true),
            manifest: minimalManifest(name: "One")
        )
        try writePackage(
            at: ambiguous.appendingPathComponent("two", isDirectory: true),
            manifest: minimalManifest(name: "Two")
        )
        let crxOnly = root.appendingPathComponent("crx-only", isDirectory: true)
        try FileManager.default.createDirectory(
            at: crxOnly,
            withIntermediateDirectories: true
        )
        try Data("Cr24".utf8).write(
            to: crxOnly.appendingPathComponent("package.crx"),
            options: [.atomic]
        )

        let ambiguousReport =
            ChromeMV3PasswordManagerRealPackageTrialRunner.run(
                rootURL: root.appendingPathComponent("ambiguous-run"),
                targets: [
                    testTarget(
                        id: "ambiguous-onepassword",
                        targetClass: .onePassword,
                        root: ambiguous
                    ),
                ],
                writeReport: false,
                now: { Date(timeIntervalSince1970: 13) }
            )
        let crxReport = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root.appendingPathComponent("crx-run"),
            targets: [
                testTarget(
                    id: "crx-bitwarden",
                    targetClass: .bitwarden,
                    root: crxOnly
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 14) }
        )

        XCTAssertEqual(
            ambiguousReport.targetConfigurations.first?.detectedPackageKind,
            .ambiguous
        )
        XCTAssertEqual(
            ambiguousReport.rows.first?.packageSource,
            .fixtureFallback
        )
        XCTAssertEqual(
            crxReport.targetConfigurations.first?.detectedPackageKind,
            .blockedCrxTrustPolicyRequired
        )
        XCTAssertEqual(crxReport.rows.first?.packageSource, .fixtureFallback)
        XCTAssertTrue(crxReport.rows.first?.packageBlockers.contains {
            $0.contains("CRX")
        } == true)
    }

    func testManifestExtractionPopupContentPermissionAndNativeDiagnostics()
        throws
    {
        let root = try temporaryDirectory(named: "real-diagnostic-rich")
        let package = root.appendingPathComponent("onepassword", isDirectory: true)
        let manifest = diagnosticRichManifest()
        try writePackage(
            at: package,
            manifest: manifest,
            extraFiles: [
                "content.css": "body { color: inherit; }",
                "popup.js":
                    "chrome.identity.getAuthToken(); chrome.runtime."
                    + "connect"
                    + #"Native("com.example.fixture_host");"#,
                "rules_1.json": "[]",
            ]
        )
        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "onepassword-rich",
                    targetClass: .onePassword,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 15) }
        )
        let row = try XCTUnwrap(report.rows.first)

        XCTAssertEqual(row.packageSource, .realLocalUnpacked)
        XCTAssertEqual(row.manifest, .pass)
        XCTAssertTrue(row.manifestRequirements.declaresNativeMessaging)
        XCTAssertTrue(row.manifestRequirements.declaresOffscreen)
        XCTAssertTrue(row.manifestRequirements.declaresIdentity)
        XCTAssertTrue(row.manifestRequirements.declaresDNR)
        XCTAssertTrue(row.manifestRequirements.declaresWebRequest)
        XCTAssertTrue(
            row.manifestRequirements.detectedNativeHostNames
                .contains("com.example.fixture_host")
        )
        XCTAssertEqual(row.css, .partial)
        XCTAssertEqual(row.mainWorld, .unsafeWithoutReview)
        XCTAssertEqual(row.multiFrame, .deferred)
        XCTAssertEqual(row.nativeMessaging, .blocked)
        XCTAssertEqual(row.dnrWebRequest, .deferred)
        XCTAssertEqual(row.sidePanelOffscreenIdentity, .deferred)
        XCTAssertFalse(row.permissionActiveTabSmoke.silentlyGranted)
        XCTAssertTrue(row.permissionActiveTabSmoke.urlTitleRedactionTested)
        XCTAssertTrue(row.nativeMessagingSmoke.noTrustedHostConfigured)
        XCTAssertEqual(
            row.nativeMessagingSmoke.exactBlocker,
            .hostRequiredButNotConfigured
        )
        XCTAssertTrue(row.nativeMessagingSmoke.arbitraryHostDiscoveryBlocked)
        XCTAssertTrue(row.nativeMessagingSmoke.realVendorHostLaunchBlocked)
        XCTAssertTrue(row.popupOptionsSmoke.blockedAPIs.contains {
            $0.namespace == "identity"
        })
        XCTAssertFalse(row.contentScriptSmoke.blockers.contains("cssUnsupported"))
        XCTAssertTrue(row.contentScriptSmoke.blockers.contains("unsupportedWorld"))
        XCTAssertTrue(row.contentScriptSmoke.blockers.contains("frameBehaviorUnsupported"))
        XCTAssertTrue(row.fixtureDelta.realAPIsAbsentInFixture.isEmpty == false)
    }

    @MainActor
    func testManagerDisplaysRealPackageStatusAndFixtureDelta() throws {
        let root = try temporaryDirectory(named: "manager-real-package")
        let package = root.appendingPathComponent("proton", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Proton Pass Local")
        )
        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "proton-manager",
                    targetClass: .protonPass,
                    root: package
                ),
            ],
            serviceWorkerTrialGateSource: .explicitTestTrial,
            writeReport: true,
            now: { Date(timeIntervalSince1970: 16) }
        )
        let expectedPackagePath = package.standardizedFileURL.path
        let record = try XCTUnwrap(
            ChromeMV3ExtensionLifecycleRegistry(rootURL: root)
                .listLifecycleRecords()
                .first {
                    $0.sourcePath == expectedPackagePath
                        || $0.displayName == "Proton Pass Local"
                }
        )
        let detail = try XCTUnwrap(
            ChromeMV3ExtensionManagerViewModelBuilder.makeDetailViewModel(
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID,
                gate: ChromeMV3ExtensionManagerGate.evaluate(
                    moduleEnabled: true
                )
            )
        )
        let summary = try XCTUnwrap(
            detail.passwordManagerCompatibilitySummary
        )

        XCTAssertEqual(report.rows.first?.targetClass, .protonPass)
        XCTAssertEqual(summary.realPackageSource, .realLocalUnpacked)
        XCTAssertEqual(
            summary.realPackageDetectedKind,
            .unpackedExtensionRoot
        )
        XCTAssertEqual(summary.realPackageTrialStatus, .blocked)
        XCTAssertEqual(summary.nativeFixtureRootState, .notRequired)
        XCTAssertEqual(summary.nativeBlockerState, .notRequired)
        XCTAssertNotNil(summary.realVendorHostDiscoveryBlockedDisclaimer)
        XCTAssertEqual(
            summary.realPackageReportFileName,
            ChromeMV3PasswordManagerRealPackageCompatibilityReport
                .reportFileName
        )
        XCTAssertFalse(summary.fixtureVsRealDeltaSummary.isEmpty)
        XCTAssertTrue(
            summary.notPublicSupportDisclaimer.contains("default-off")
        )
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.readiness?
                .backgroundServiceWorkerPath,
            "background.js"
        )
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.readiness?
                .localExperimentalGateState,
            .runtimeGateBlocked
        )
        XCTAssertNil(detail.serviceWorkerReadinessPanel.lastEventResult)
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .gateState,
            .closedAfterTrial
        )
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .targetID,
            "proton-manager"
        )
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .realPackageSource,
            .realLocalUnpacked
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .importScriptsResult.hasPrefix("notRequired:") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .dynamicImportRewriteResult.hasPrefix("notRequired:") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .computedImportScriptsResult.hasPrefix("notRequired:") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .timerPolicyResult.contains("wallClock=false") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .timerShimResult.hasPrefix("drained:") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .moduleWorkerReadinessResult.hasPrefix("notRequired:") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .i18nCapabilityResult.contains("getUILanguage=true") == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .runtimeLastErrorObjectShapeResult.contains(
                    "active message is a primitive string"
                ) == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .runtimeLastErrorCallbackLifecycleResult.contains(
                    "cleared in finally"
                ) == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .workerGlobalEventTargetResult.contains(
                    "windowDocumentExposed=false"
                ) == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .fetchClassificationResult.contains("networkExecution=false")
                == true
        )
        XCTAssertTrue(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .dispatchSmokeResult.hasPrefix("notAttempted:") == true
        )
        XCTAssertEqual(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .nextBlockerClassification,
            .otherPreciseBlocker
        )
        XCTAssertFalse(
            detail.serviceWorkerReadinessPanel.latestRealPackageTrialReport?
                .nextRecommendedFix.isEmpty ?? true
        )
    }

    func testMissingNativeFixtureRootIsReportedNotFailure() throws {
        let root = try temporaryDirectory(named: "missing-native-fixture-root")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        let hostName = "com.example.fixture_host"
        try writePackage(
            at: package,
            manifest: nativeManifest(name: "Bitwarden Local"),
            extraFiles: [
                "popup.js":
                    "chrome.runtime."
                    + "send"
                    + #"NativeMessage("com.example.fixture_host", {});"#,
            ]
        )
        let fixtureRoot = root.appendingPathComponent(
            "native-host-fixtures/bitwarden",
            isDirectory: true
        )
        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "bitwarden-native-missing-root",
                    targetClass: .bitwarden,
                    root: package,
                    fixtureRoot: fixtureRoot,
                    hostNames: [hostName]
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 18) }
        )
        let row = try XCTUnwrap(report.rows.first)
        let readiness = try XCTUnwrap(
            row.nativeMessagingSmoke.hostReadiness.first
        )

        XCTAssertEqual(row.packageSource, .realLocalUnpacked)
        XCTAssertEqual(row.nativeMessagingSmoke.fixtureRootState, .missingFixtureRoot)
        XCTAssertFalse(row.nativeMessagingSmoke.noTrustedHostConfigured)
        XCTAssertEqual(row.nativeMessagingSmoke.exactBlocker, .hostRequiredButNotConfigured)
        XCTAssertEqual(readiness.hostName, hostName)
        XCTAssertEqual(readiness.blockerState, .hostRequiredButNotConfigured)
        XCTAssertFalse(readiness.exchangeResult.attempted)
        XCTAssertFalse(report.arbitraryNativeHostDiscoveryAttempted)
        XCTAssertFalse(report.realVendorNativeHostLaunchAttempted)
    }

    func testAllowedOriginsMismatchBlocksConfiguredFixtureHost() throws {
        let root = try temporaryDirectory(named: "native-fixture-origin-mismatch")
        let package = root.appendingPathComponent("onepassword", isDirectory: true)
        let fixtureRoot = root.appendingPathComponent(
            "native-host-fixtures/onepassword",
            isDirectory: true
        )
        let hostName = "com.example.fixture_host"
        try writePackage(
            at: package,
            manifest: nativeManifest(name: "1Password Local"),
            extraFiles: [
                "popup.js":
                    "chrome.runtime."
                    + "connect"
                    + #"Native("com.example.fixture_host");"#,
            ]
        )
        _ = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "onepassword-origin-mismatch",
            fixtureRootURL: fixtureRoot,
            baseHostName: hostName,
            extensionID: "abcdefghijklmnopabcdefghijklmnop",
            protocols: [.echo]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "onepassword-origin-mismatch",
                    targetClass: .onePassword,
                    root: package,
                    fixtureRoot: fixtureRoot,
                    hostNames: [hostName]
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 19) }
        )
        let readiness = try XCTUnwrap(
            report.rows.first?.nativeMessagingSmoke.hostReadiness.first
        )

        XCTAssertEqual(readiness.fixtureRootState, .configured)
        XCTAssertEqual(readiness.manifestState, .valid)
        XCTAssertEqual(readiness.allowedOriginsState, .mismatch)
        XCTAssertEqual(readiness.blockerState, .allowedOriginsMismatch)
        XCTAssertFalse(readiness.exchangeResult.attempted)
        XCTAssertTrue(readiness.remediation.contains("allowed_origins"))
    }

    func testNativeMessagingPermissionMissingBlocksConfiguredFixtureHost()
        throws
    {
        let root = try temporaryDirectory(named: "native-fixture-permission-missing")
        let package = root.appendingPathComponent("proton", isDirectory: true)
        let fixtureRoot = root.appendingPathComponent(
            "native-host-fixtures/proton",
            isDirectory: true
        )
        let hostName = "com.example.fixture_host"
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Proton Pass Local"),
            extraFiles: [
                "popup.js":
                    "chrome.runtime."
                    + "send"
                    + #"NativeMessage("com.example.fixture_host", {});"#,
            ]
        )
        let first = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "proton-permission-missing",
                    targetClass: .protonPass,
                    root: package,
                    fixtureRoot: fixtureRoot,
                    hostNames: [hostName]
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 20) }
        )
        let extensionID = try XCTUnwrap(
            first.rows.first?.nativeMessagingSmoke.detectedExtensionID
        )
        _ = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "proton-permission-missing",
            fixtureRootURL: fixtureRoot,
            baseHostName: hostName,
            extensionID: extensionID,
            protocols: [.echo]
        )
        let second = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "proton-permission-missing",
                    targetClass: .protonPass,
                    root: package,
                    fixtureRoot: fixtureRoot,
                    hostNames: [hostName]
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 21) }
        )
        let readiness = try XCTUnwrap(
            second.rows.first?.nativeMessagingSmoke.hostReadiness.first
        )

        XCTAssertEqual(readiness.manifestState, .valid)
        XCTAssertEqual(readiness.allowedOriginsState, .compatible)
        XCTAssertEqual(readiness.nativeMessagingPermissionState, .missing)
        XCTAssertEqual(readiness.blockerState, .permissionMissing)
        XCTAssertFalse(readiness.exchangeResult.attempted)
    }

    func testApprovedFixtureHostAllowsSendAndConnectExchange() throws {
        let root = try temporaryDirectory(named: "native-fixture-approved")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        let fixtureRoot = root.appendingPathComponent(
            "native-host-fixtures/bitwarden",
            isDirectory: true
        )
        let hostName = "com.example.fixture_host"
        let profileID = "approved-native-profile"
        try writePackage(
            at: package,
            manifest: nativeManifest(name: "Bitwarden Local"),
            extraFiles: [
                "popup.js":
                    "chrome.runtime."
                    + "connect"
                    + #"Native("com.example.fixture_host");"#,
            ]
        )
        let target = testTarget(
            id: "bitwarden-approved-native",
            targetClass: .bitwarden,
            root: package,
            fixtureRoot: fixtureRoot,
            hostNames: [hostName]
        )
        let first = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [target],
            profileID: profileID,
            writeReport: false,
            now: { Date(timeIntervalSince1970: 22) }
        )
        let extensionID = try XCTUnwrap(
            first.rows.first?.nativeMessagingSmoke.detectedExtensionID
        )
        _ = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "bitwarden-approved-native",
            fixtureRootURL: fixtureRoot,
            baseHostName: hostName,
            extensionID: extensionID,
            protocols: [.echo]
        )
        let targetProfileID =
            "\(profileID)-\(ChromeMV3PasswordManagerRealPackageClass.bitwarden.fixtureFallbackKind.pathComponent)"
        let approval =
            ChromeMV3NativeTrustedHostPolicyFactory
            .recordForExplicitDeveloperPreviewApproval(
                hostName: hostName,
                extensionID: extensionID,
                profileID: targetProfileID,
                lookupPolicy: ChromeMV3NativeHostLookupPolicy.macOS(
                    explicitTestRootPath: fixtureRoot.path
                ),
                permissionState: .grantedByManifest,
                approvedRootPaths: [fixtureRoot.path],
                sequence: 1,
                now: Date(timeIntervalSince1970: 23)
            )
            .record
        let second = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [target],
            profileID: profileID,
            trustedHostApprovalRecords: [approval],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 24) }
        )
        let smoke = try XCTUnwrap(second.rows.first?.nativeMessagingSmoke)
        let readiness = try XCTUnwrap(smoke.hostReadiness.first)

        XCTAssertEqual(readiness.fixtureRootState, .configured)
        XCTAssertEqual(smoke.fixturePack?.generatedState, .generated)
        XCTAssertEqual(smoke.fixturePack?.validatedState, .valid)
        XCTAssertEqual(readiness.fixturePackGeneratedState, .generated)
        XCTAssertEqual(readiness.fixturePackValidatedState, .valid)
        XCTAssertEqual(
            readiness.hostNameSource,
            "configuredTarget+fixtureMetadata+observedRuntimeCall+selectedFixtureMetadata"
        )
        XCTAssertEqual(readiness.allowedOriginsSource, "fixtureManifest.allowed_origins")
        XCTAssertEqual(readiness.manifestState, .valid)
        XCTAssertEqual(readiness.allowedOriginsState, .compatible)
        XCTAssertEqual(readiness.trustedHostApprovalState, .trustedForDeveloperPreview)
        XCTAssertEqual(readiness.blockerState, .approvedTrustedFixtureHostWorks)
        XCTAssertTrue(readiness.exchangeResult.attempted)
        XCTAssertEqual(readiness.exchangeResult.state, .succeeded)
        XCTAssertTrue(readiness.exchangeResult.sendNativeMessageSucceeded)
        XCTAssertTrue(readiness.exchangeResult.connectNativeSucceeded)
        XCTAssertTrue(readiness.exchangeResult.postMessageSucceeded)
        XCTAssertTrue(readiness.exchangeResult.disconnectSucceeded)
        XCTAssertTrue(readiness.exchangeResult.fixtureProcessLaunchAttempted)
        XCTAssertFalse(readiness.exchangeResult.productProcessLaunchAttempted)
        XCTAssertTrue(smoke.fixtureExchangeSucceeded)
        XCTAssertEqual(smoke.sendNativeMessageReadiness, "ready")
        XCTAssertEqual(smoke.connectNativeReadiness, "ready")
    }

    func testRealPackageSourceGuardsRemainLocalAndDiagnosticsOnly() throws {
        let root = projectRoot()
        let source = try String(
            contentsOf:
                root.appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerRealPackageCompatibility.swift"
                ),
            encoding: .utf8
        )
        let validator = try String(
            contentsOf:
                root.appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3ManifestValidator.swift"
                ),
            encoding: .utf8
        )
        let harness = try String(
            contentsOf:
                root.appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3ServiceWorkerJSExecutionHarness.swift"
                ),
            encoding: .utf8
        )
        let positive = "tr" + "ue"

        XCTAssertFalse(source.contains("URL" + "Session"))
        XCTAssertFalse(source.contains("Process" + "("))
        XCTAssertFalse(source.contains("DispatchSource" + "Ti" + "mer"))
        XCTAssertFalse(source.contains("Ti" + "mer" + "("))
        XCTAssertFalse(source.contains("chrome.webstore" + ".install"))
        XCTAssertFalse(source.contains("clients2.google.com/service/update2/crx"))
        XCTAssertFalse(source.contains("WKContentRuleListStore"))
        XCTAssertFalse(source.contains("compileContentRuleList"))
        XCTAssertFalse(source.contains("nativeHostScanningAllowed = " + positive))
        XCTAssertFalse(source.contains("arbitraryHostLaunchAllowed = " + positive))
        XCTAssertFalse(source.contains("productRuntimeAvailable: " + positive))
        XCTAssertFalse(source.contains("productRuntimeExposed: " + positive))
        XCTAssertFalse(harness.contains("networkImportsAllowed: " + positive))
        XCTAssertFalse(harness.contains("filesystemAbsoluteImportsAllowed: " + positive))
        XCTAssertFalse(harness.contains("dynamicImportAvailable: " + positive))
        XCTAssertFalse(harness.contains("moduleWorkerImportAvailable: " + positive))
        XCTAssertFalse(harness.contains("permanentBackgroundAvailable: " + positive))
        XCTAssertFalse(
            harness.contains("webCryptoAvailableByDefault: " + positive)
        )
        XCTAssertFalse(
            harness.contains(
                "subtleCryptoAvailableByDefault: " + positive
            )
        )
        XCTAssertFalse(
            harness.contains("i18nGetUILanguageAvailableByDefault: " + positive)
        )
        XCTAssertFalse(
            harness.contains(
                "workerGlobalEventTargetAvailableByDefault: " + positive
            )
        )
        XCTAssertFalse(harness.contains("workerGlobalWindowDocumentExposed: " + positive))
        XCTAssertFalse(harness.contains("fetchAvailableByDefault: " + positive))
        XCTAssertFalse(harness.contains("networkFetchAllowed: " + positive))
        XCTAssertFalse(
            harness.contains("fetchNetworkExecutionAllowed: " + positive)
        )
        XCTAssertFalse(harness.contains("credentialsAllowed: " + positive))
        XCTAssertFalse(harness.contains("cacheAllowed: " + positive))
        XCTAssertTrue(harness.contains("generatedBundleOnly: " + positive))
        XCTAssertFalse(harness.contains("SystemRandomNumberGenerator"))
        XCTAssertTrue(harness.contains("SecRandomCopyBytes(kSecRandomDefault"))
        XCTAssertTrue(
            harness.contains(
                "No dummy keys, signatures, ciphertexts, or derived bits are returned."
            )
        )
        XCTAssertTrue(
            harness.contains(
                "return Promise.reject(new DOMException("
            )
        )
        XCTAssertFalse(harness.contains("defineWorkerGlobal('window'"))
        XCTAssertFalse(harness.contains("defineWorkerGlobal('document'"))
        XCTAssertFalse(harness.contains("globalThis.window ="))
        XCTAssertFalse(harness.contains("globalThis.document ="))
        XCTAssertFalse(harness.contains("DispatchSource" + "Ti" + "mer"))
        XCTAssertFalse(harness.contains("Ti" + "mer" + "("))
        XCTAssertFalse(validator.contains("manifest_version 2 only"))
    }

    func testWritesIgnoredRealPackageCompatibilityReportArtifact() throws {
        let reportRoot = projectRoot()
            .appendingPathComponent(".diagnostics", isDirectory: true)
            .appendingPathComponent(
                "chrome-mv3-real-package-trials",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: reportRoot,
            withIntermediateDirectories: true
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: reportRoot,
            serviceWorkerTrialGateSource: .explicitTestTrial,
            writeReport: true,
            now: { Date(timeIntervalSince1970: 17) }
        )
        let reportURL =
            ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
            .reportURL(rootURL: reportRoot)
        let decoded = try decodeReport(reportURL)

        XCTAssertEqual(decoded.rows.count, 3)
        XCTAssertEqual(
            decoded.rows.map(\.targetID),
            report.rows.map(\.targetID)
        )
        XCTAssertEqual(
            decoded.rows.map(\.targetClass),
            report.rows.map(\.targetClass)
        )
        XCTAssertTrue(decoded.noWebStoreInstallAttempted)
        XCTAssertTrue(decoded.noRemoteCRXDownloadAttempted)
        XCTAssertTrue(decoded.noRealCredentialsUsed)
        XCTAssertFalse(decoded.arbitraryNativeHostDiscoveryAttempted)
        XCTAssertFalse(decoded.realVendorNativeHostLaunchAttempted)
        XCTAssertFalse(decoded.productRuntimeAvailable)
        XCTAssertFalse(decoded.productRuntimeExposed)
        XCTAssertTrue(decoded.rows.allSatisfy {
            $0.serviceWorkerEventReadiness.executionStartResult != nil
                && $0.serviceWorkerEventReadiness.gateClosedAfterTrial
                && $0.serviceWorkerEventReadiness.trialGateRecords.last?
                .state == .closedAfterTrial
        })
        XCTAssertTrue(
            decoded.rows.first {
                $0.targetClass == .onePassword
            }?.serviceWorkerEventReadiness.resourceLoadResult?.blockers
                .contains(.moduleWorkerUnsupported) == true
        )
        let byClass = Dictionary(
            uniqueKeysWithValues: decoded.rows.map { ($0.targetClass, $0) }
        )
        let bitwarden = try XCTUnwrap(byClass[.bitwarden])
        let onePassword = try XCTUnwrap(byClass[.onePassword])
        let proton = try XCTUnwrap(byClass[.protonPass])
        XCTAssertEqual(
            bitwarden.serviceWorkerEventReadiness.nextBlockerClassification,
            .unsupportedChromeAPI
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("chrome.alarms.create")
        )
        XCTAssertEqual(
            bitwarden.serviceWorkerEventReadiness.deviceFailureClassification,
            .resolvedWorkerNavigatorBrowserFamilySignal
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.deviceFailureDetail
                .contains("without inserting fake device identity")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.workerNavigatorUserAgentResult
                .contains("Chrome/0")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.precedingChromeAPICalls
                .contains("chrome.i18n.getUILanguage")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.storageOperationSummary
                .allSatisfy {
                    !$0.contains("token")
                        && !$0.contains("secret")
                        && !$0.contains("vault")
                }
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.fetchClassificationSummary
                .contains {
                    $0.contains("b9f569e387bfc3d589be.module.wasm")
                        && $0.contains("allowed=true")
                        && $0.contains("status=200")
                }
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness
                .generatedBundleFetchResourceSummary.contains {
                    $0.contains("b9f569e387bfc3d589be.module.wasm")
                        && $0.contains(":copied:none")
                }
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.webAssemblyCapabilityResult
                .contains("instantiate=true")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.webAssemblyCapabilityResult
                .contains("instantiateStreaming=false")
        )
        XCTAssertFalse(
            bitwarden.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("fetch remains classified but disabled")
        )
        XCTAssertFalse(
            bitwarden.serviceWorkerEventReadiness.fetchClassificationSummary
                .contains { $0.contains("notCopiedGeneratedResource") }
        )
        XCTAssertFalse(
            bitwarden.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("chrome.i18n.getUILanguage")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.i18nCapabilityResult
                .contains("getUILanguage=true")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.i18nOperationSummary
                .contains {
                    $0.hasPrefix(
                        "chrome.i18n.getUILanguage:fulfilled:"
                    )
                }
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.fetchClassificationResult
                .contains("networkExecution=false")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.cryptoCapabilityResult
                .contains("subtleMethods=digest")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.jsExecutionPolicy
                .webCryptoAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(
            bitwarden.serviceWorkerEventReadiness.jsExecutionPolicy
                .webCryptoAvailableByDefault
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness
                .cryptoSubtleSupportedAlgorithms.contains("digest:SHA-256")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness
                .cryptoSubtleBlockedAlgorithms.contains("PBKDF2")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.dynamicImportRewriteResult
                .hasPrefix("notRequired:")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.importScriptsResult
                .contains("719.background.js")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.computedImportScriptsResult
                .hasPrefix("resolved:")
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.dependencyInventory
                .dynamicImportExpressions.isEmpty
        )
        XCTAssertNotEqual(
            bitwarden.serviceWorkerEventReadiness.executionStartResult?
                .exceptionDetails?.classification,
            .missingWebAPI
        )
        XCTAssertNotEqual(
            bitwarden.serviceWorkerEventReadiness.executionStartResult?
                .exceptionDetails?.inferredMissingProperty,
            "crypto.subtle"
        )
        XCTAssertTrue(
            bitwarden.serviceWorkerEventReadiness.dependencyInventory
                .importScriptsCalls.contains {
                    $0.shape == .concatenation
                        || $0.shape == .unknownComputed
                }
        )
        XCTAssertEqual(
            onePassword.serviceWorkerEventReadiness.nextBlockerClassification,
            .moduleWorkerUnsupported
        )
        XCTAssertTrue(
            onePassword.serviceWorkerEventReadiness.dependencyInventory
                .moduleWorkerInventory.declaredAsModuleWorker
        )
        XCTAssertTrue(
            onePassword.serviceWorkerEventReadiness.dynamicImportRewriteResult
                .hasPrefix("notRequired:")
        )
        XCTAssertTrue(
            onePassword.serviceWorkerEventReadiness.moduleWorkerReadinessResult
                .hasPrefix("blocked:")
        )
        XCTAssertNil(
            onePassword.serviceWorkerEventReadiness.executionStartResult?
                .exceptionDetails
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.workerGlobalEventTargetResult
                .contains("addEventListener/removeEventListener/dispatchEvent=true")
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.workerGlobalEventTargetResult
                .contains("windowDocumentExposed=false")
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.cryptoCapabilityResult
                .contains("fulfilled=")
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.cryptoOperationSummary
                .contains("getRandomValues:none:fulfilled:none")
        )
        XCTAssertGreaterThan(
            proton.serviceWorkerEventReadiness.dependencyInventory
                .asyncAPIInventory.count(.setTimeout),
            0
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.dependencyInventory
                .importScriptsCalls.contains {
                    $0.shape == .concatenation
                        || $0.shape == .unknownComputed
                }
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("addEventListener is not a function")
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness
                .workerWindowFailureClassification
                .hasPrefix("workerGlobalEventTargetMissing:")
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.workerGlobalEventSummary
                .contains { $0.hasPrefix("addEventListener:") }
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.dispatchSmokeResult
                .contains("asyncCompletionUnsupported") == false
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("setTimeout")
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("rp.runtime")
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness.nextBlockerDetail
                .contains("rp.tabs.onUpdated")
        )
        XCTAssertFalse(
            proton.serviceWorkerEventReadiness.nextBlockerDetail
                .contains(
                    "chrome.runtime.lastError.message.Symbol(Symbol.toPrimitive)"
                )
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness
                .runtimeLastErrorObjectShapeResult.contains(
                    "active message is a primitive string"
                )
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness
                .runtimeLastErrorCallbackLifecycleResult.contains(
                    "visible during callback execution"
                )
        )
        XCTAssertTrue(
            proton.serviceWorkerEventReadiness.timerShimResult
                .hasPrefix("available:")
                || proton.serviceWorkerEventReadiness.timerShimResult
                    .hasPrefix("drained:")
        )
        XCTAssertTrue(decoded.rows.allSatisfy {
            $0.serviceWorkerEventReadiness.importScriptsResult.isEmpty == false
                && $0.serviceWorkerEventReadiness.dynamicImportRewriteResult
                    .isEmpty == false
                && $0.serviceWorkerEventReadiness.computedImportScriptsResult
                    .isEmpty == false
                && $0.serviceWorkerEventReadiness.timerShimResult.isEmpty
                    == false
                && $0.serviceWorkerEventReadiness
                    .moduleWorkerReadinessResult.isEmpty == false
                && $0.serviceWorkerEventReadiness
                    .i18nCapabilityResult.isEmpty == false
                && $0.serviceWorkerEventReadiness
                    .workerGlobalEventTargetResult.isEmpty == false
                && $0.serviceWorkerEventReadiness
                    .fetchClassificationResult.isEmpty == false
                && $0.serviceWorkerEventReadiness
                    .runtimeLastErrorObjectShapeResult.isEmpty == false
                && $0.serviceWorkerEventReadiness
                    .runtimeLastErrorCallbackLifecycleResult.isEmpty == false
                && $0.serviceWorkerEventReadiness.dispatchSmokeResult.isEmpty
                    == false
        })
    }

    func testServiceWorkerInventoryClassifiesDynamicImportShapes()
        throws
    {
        let root = try temporaryDirectory(named: "dynamic-import-inventory")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Dynamic Inventory"),
            extraFiles: [
                "background.js": """
                import('./literal.js');
                import(`./static-template.js`);
                import(`./${name}.js`);
                import(chunkID);
                import(loader.path);
                import(makePath());
                import(flag ? './a.js' : './b.js');
                import('./chunks/' + name + '.js');
                import({ path: './object.js' });
                import('https://example.com/remote.js');
                """,
                "literal.js": "",
                "static-template.js": "",
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "dynamic-inventory",
                    targetClass: .bitwarden,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 18) }
        )
        let inventory = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
                .dependencyInventory
        )
        let shapes = Set(inventory.dynamicImportExpressions.map(\.shape))

        XCTAssertTrue(shapes.contains(.stringLiteralLocal))
        XCTAssertTrue(shapes.contains(.templateLiteralStatic))
        XCTAssertTrue(shapes.contains(.templateLiteralDynamic))
        XCTAssertTrue(shapes.contains(.identifier))
        XCTAssertTrue(shapes.contains(.memberExpression))
        XCTAssertTrue(shapes.contains(.callExpression))
        XCTAssertTrue(shapes.contains(.conditionalExpression))
        XCTAssertTrue(shapes.contains(.concatenation))
        XCTAssertTrue(shapes.contains(.unknownComputed))
        XCTAssertTrue(shapes.contains(.remoteOrUnsafe))
        XCTAssertTrue(inventory.dynamicImportExpressions.contains {
            $0.specifierPreview == "'./literal.js'"
                && $0.dependencyCandidatePath == "literal.js"
                && $0.generatedRootContained == false
        })
        XCTAssertFalse(
            report.rows.first?.serviceWorkerEventReadiness
                .jsExecutionPolicy.dynamicImportAvailable == true
        )
    }

    func testServiceWorkerInventoryClassifiesModuleGraph()
        throws
    {
        let root = try temporaryDirectory(named: "module-inventory")
        let package = root.appendingPathComponent("onepassword", isDirectory: true)
        var manifest = minimalManifest(name: "Module Inventory")
        manifest["background"] = [
            "service_worker": "background/module.js",
            "type": "module",
        ]
        try writePackage(
            at: package,
            manifest: manifest,
            extraFiles: [
                "background/module.js": """
                import './module-listener.js';
                import value from './module-export.js';
                export const ready = true;
                await Promise.resolve(value);
                """,
                "background/module-listener.js":
                    "chrome.runtime.onMessage.addListener(() => {});",
                "background/module-export.js": "export default 1;",
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "module-inventory",
                    targetClass: .onePassword,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 19) }
        )
        let inventory = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
                .dependencyInventory
        )
        XCTAssertTrue(inventory.moduleWorkerInventory.declaredAsModuleWorker)
        XCTAssertEqual(
            inventory.moduleWorkerInventory.staticImportDeclarations
                .map(\.dependencyCandidatePath)
                .compactMap { $0 }
                .sorted(),
            ["background/module-export.js", "background/module-listener.js"]
        )
        XCTAssertTrue(
            inventory.moduleWorkerInventory.staticImportDeclarations
                .allSatisfy { $0.generatedRootContained == false }
        )
        XCTAssertGreaterThan(
            inventory.moduleWorkerInventory.exportUsageLocations.count,
            0
        )
        XCTAssertTrue(inventory.moduleWorkerInventory.topLevelAwaitDetected)
        XCTAssertEqual(
            inventory.listenerRegistrationMap.moduleDependencyCandidateCount,
            1
        )
        XCTAssertEqual(
            report.rows.first?.serviceWorkerEventReadiness
                .nextBlockerClassification,
            .moduleWorkerUnsupported
        )
        XCTAssertFalse(
            report.rows.first?.serviceWorkerEventReadiness
                .jsExecutionPolicy.moduleWorkerImportAvailable == true
        )
        let readiness = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
        )
        XCTAssertTrue(
            readiness.jsExecutionPolicy.moduleWorkerReadinessProbe
                .probeExecuted
        )
        XCTAssertTrue(
            readiness.jsExecutionPolicy.moduleWorkerReadinessProbe
                .staticImportGraphInspectionAvailable
        )
        XCTAssertFalse(
            readiness.jsExecutionPolicy.moduleWorkerReadinessProbe
                .sourceTextModuleLoaderAvailable
        )
        XCTAssertTrue(
            readiness.moduleWorkerReadinessResult.contains(
                "sourceTextModuleLoaderUnavailable"
            )
        )
    }

    func testServiceWorkerInventoryClassifiesTimerAndAsyncAPIs()
        throws
    {
        let root = try temporaryDirectory(named: "async-api-inventory")
        let package = root.appendingPathComponent("proton", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Async Inventory"),
            extraFiles: [
                "background.js": """
                setTimeout(() => {}, 1);
                setInterval(() => {}, 2);
                queueMicrotask(() => {});
                Promise.resolve().then(() => {});
                async function load() { return fetch('/local.json'); }
                const fn = async () => new WebSocket('wss://example.test');
                const es = new EventSource('/events');
                """,
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "async-inventory",
                    targetClass: .protonPass,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 20) }
        )
        let asyncInventory = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
                .dependencyInventory.asyncAPIInventory
        )

        XCTAssertEqual(asyncInventory.count(.setTimeout), 1)
        XCTAssertEqual(asyncInventory.count(.setInterval), 1)
        XCTAssertEqual(asyncInventory.count(.queueMicrotask), 1)
        XCTAssertEqual(asyncInventory.count(.promiseThen), 1)
        XCTAssertEqual(asyncInventory.count(.asyncFunction), 2)
        XCTAssertEqual(asyncInventory.count(.fetch), 1)
        XCTAssertEqual(asyncInventory.count(.webSocket), 1)
        XCTAssertEqual(asyncInventory.count(.eventSource), 1)
        let fetchClassifications =
            try XCTUnwrap(
                report.rows.first?.serviceWorkerEventReadiness
                    .dependencyInventory.fetchClassifications
            )
        XCTAssertEqual(fetchClassifications.count, 1)
        XCTAssertEqual(
            fetchClassifications.first?.requestKind,
            .missingResource
        )
        XCTAssertEqual(
            fetchClassifications.first?.blocker,
            "missingResource"
        )
        XCTAssertEqual(fetchClassifications.first?.executionAllowed, false)
        XCTAssertTrue(
            report.rows.first?.serviceWorkerEventReadiness
                .fetchClassificationSummary.contains {
                    $0.contains("missingResource")
                        && $0.contains("allowed=false")
                } == true
        )
        XCTAssertFalse(
            report.rows.first?.serviceWorkerEventReadiness
                .jsExecutionPolicy.timersAllowed == true
        )
    }

    func testServiceWorkerInventoryMapsListenerRegistrationSources()
        throws
    {
        let root = try temporaryDirectory(named: "listener-map-inventory")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Listener Inventory"),
            extraFiles: [
                "background.js": """
                importScripts('imported.js');
                import('./dynamic-listener.js');
                import(computedChunk);
                importScripts(computedScript);
                chrome.runtime.onInstalled.addListener(() => {});
                """,
                "imported.js":
                    "chrome.runtime.onMessage.addListener(() => {});",
                "dynamic-listener.js":
                    "chrome.runtime.onConnect.addListener(() => {});",
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "listener-map",
                    targetClass: .bitwarden,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 21) }
        )
        let map = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
                .dependencyInventory.listenerRegistrationMap
        )

        XCTAssertEqual(map.mainWorkerCount, 1)
        XCTAssertEqual(map.importScriptsDependencyCount, 1)
        XCTAssertEqual(map.dynamicImportCandidateCount, 1)
        XCTAssertEqual(map.unknownComputedDependencyReferenceCount, 2)
        XCTAssertTrue(map.registrations.contains {
            $0.sourceKind == .importScriptsDependency
                && $0.sourcePath == "imported.js"
        })
        XCTAssertTrue(map.registrations.contains {
            $0.sourceKind == .dynamicImportCandidate
                && $0.sourcePath == "dynamic-listener.js"
        })
    }

    func testServiceWorkerInventoryDoesNotEnableRuntimeBehavior()
        throws
    {
        let root = try temporaryDirectory(named: "inventory-runtime-guard")
        let package = root.appendingPathComponent("bitwarden", isDirectory: true)
        try writePackage(
            at: package,
            manifest: minimalManifest(name: "Runtime Guard"),
            extraFiles: [
                "background.js": """
                import('./dep.js');
                setTimeout(() => {}, 0);
                chrome.runtime.onMessage.addListener(() => {});
                """,
                "dep.js": "",
            ]
        )

        let report = ChromeMV3PasswordManagerRealPackageTrialRunner.run(
            rootURL: root,
            targets: [
                testTarget(
                    id: "runtime-guard",
                    targetClass: .bitwarden,
                    root: package
                ),
            ],
            writeReport: false,
            now: { Date(timeIntervalSince1970: 22) }
        )
        let readiness = try XCTUnwrap(
            report.rows.first?.serviceWorkerEventReadiness
        )

        XCTAssertNil(readiness.executionStartResult)
        XCTAssertGreaterThan(
            readiness.dependencyInventory.dynamicImportExpressions.count,
            0
        )
        XCTAssertFalse(
            readiness.jsExecutionPolicy
                .serviceWorkerJSExecutionAvailableByDefault
        )
        XCTAssertFalse(readiness.jsExecutionPolicy.dynamicImportAvailable)
        XCTAssertFalse(
            readiness.jsExecutionPolicy.timersAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(readiness.jsExecutionPolicy.timersAvailableByDefault)
        XCTAssertFalse(readiness.jsExecutionPolicy.wallClockTimersAllowed)
        XCTAssertFalse(readiness.jsExecutionPolicy.timersAllowed)
        XCTAssertFalse(report.productRuntimeAvailable)
        XCTAssertFalse(report.productRuntimeExposed)
    }

    func testDisabledModulePolicyRemainsZeroCostForDiagnostics()
        throws
    {
        let policy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .disabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: true,
            generatedBundleRecordAvailable: true,
            dynamicImportRewriteExperimentAllowed: true
        )

        XCTAssertFalse(
            policy.serviceWorkerJSExecutionAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(policy.dynamicImportCapabilityProbe.probeExecuted)
        XCTAssertFalse(policy.dynamicImportAvailable)
        XCTAssertFalse(policy.moduleWorkerImportAvailable)
        XCTAssertFalse(policy.moduleWorkerReadinessProbe.probeExecuted)
        XCTAssertFalse(policy.timersAvailableInLocalExperimentalGate)
        XCTAssertFalse(policy.timersAvailableByDefault)
        XCTAssertFalse(policy.wallClockTimersAllowed)
        XCTAssertFalse(
            policy.runtimeLastErrorAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(policy.runtimeLastErrorAvailableByDefault)
        XCTAssertFalse(policy.runtimeLastErrorCallbackScoped)
        XCTAssertFalse(
            policy.workerNavigatorUserAgentAvailableInLocalExperimentalGate
        )
        XCTAssertFalse(policy.workerNavigatorUserAgentAvailableByDefault)
        XCTAssertNil(policy.workerNavigatorUserAgent)
        XCTAssertFalse(
            policy.workerNavigatorChromeCompatibilityTokenAvailable
        )
        XCTAssertFalse(policy.timersAllowed)
    }

    private func testTarget(
        id: String,
        targetClass: ChromeMV3PasswordManagerRealPackageClass,
        root: URL,
        fixtureRoot: URL? = nil,
        hostNames: [String] = []
    ) -> ChromeMV3PasswordManagerRealPackageTargetDefinition {
        ChromeMV3PasswordManagerRealPackageTargetDefinition(
            targetID: id,
            displayName: "\(targetClass.rawValue) Test",
            targetClass: targetClass,
            explicitAllowedLocalRoot: root.path,
            fixtureFallbackID: targetClass.fixtureFallbackKind.rawValue,
            expectedExtensionID: nil,
            configuredNativeHostNames: hostNames,
            trustedFixtureHostRootPath: fixtureRoot?.path,
            noRealCredentialsInvariant: true
        )
    }

    private func minimalManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "permissions": ["activeTab", "storage", "tabs"],
            "host_permissions": ["https://example.com/*"],
            "action": ["default_popup": "popup.html"],
            "background": ["service_worker": "background.js"],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "run_at": "document_idle",
                ],
            ],
        ]
    }

    private func nativeManifest(name: String) -> [String: Any] {
        var manifest = minimalManifest(name: name)
        manifest["permissions"] = [
            "activeTab",
            "nativeMessaging",
            "storage",
            "tabs",
        ]
        return manifest
    }

    private func diagnosticRichManifest(
        name: String = "1Password Local"
    ) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "permissions": [
                "activeTab",
                "declarativeNetRequestWithHostAccess",
                "identity",
                "nativeMessaging",
                "offscreen",
                "storage",
                "tabs",
                "webRequest",
            ],
            "optional_permissions": ["clipboardRead"],
            "host_permissions": ["https://example.com/*"],
            "optional_host_permissions": ["https://optional.example/*"],
            "action": ["default_popup": "popup.html"],
            "options_ui": ["page": "options.html"],
            "background": [
                "service_worker": "background.js",
                "type": "module",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "css": ["content.css"],
                    "world": "MAIN",
                    "all_frames": true,
                    "match_about_blank": true,
                    "match_origin_as_fallback": true,
                    "run_at": "document_start",
                ],
            ],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "ruleset_1",
                        "enabled": true,
                        "path": "rules_1.json",
                    ],
                ],
            ],
            "content_security_policy": [
                "extension_pages": "script-src 'self'; object-src 'self'",
            ],
            "externally_connectable": [
                "matches": ["https://account.example/*"],
            ],
            "web_accessible_resources": [
                [
                    "resources": ["content.css"],
                    "matches": ["https://example.com/*"],
                ],
            ],
        ]
    }

    private func writePackage(
        at package: URL,
        manifest: [String: Any],
        extraFiles: [String: String] = [:]
    ) throws {
        try FileManager.default.createDirectory(
            at: package,
            withIntermediateDirectories: true
        )
        try manifestData(manifest).write(
            to: package.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (name, contents) in [
            "background.js": "",
            "popup.html": "<!doctype html><script src=\"popup.js\"></script>",
            "options.html": "<!doctype html>",
            "content.js": "",
            "popup.js": "",
        ].merging(extraFiles, uniquingKeysWith: { _, new in new }) {
            let url = package.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func manifestData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func decodeReport(
        _ url: URL
    ) throws -> ChromeMV3PasswordManagerRealPackageCompatibilityReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ChromeMV3PasswordManagerRealPackageCompatibilityReport.self,
            from: Data(contentsOf: url)
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3PasswordManagerRealPackageCompatibilityTests",
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

    private func makeZIPData(entries: [ZIPFixtureEntry]) -> Data {
        var archive = Data()
        var central = Data()
        var centralRecords:
            [(entry: ZIPFixtureEntry, offset: UInt32, crc: UInt32)] = []

        for entry in entries {
            let offset = UInt32(archive.count)
            let nameData = Data(entry.path.utf8)
            let crc = checksum(entry.data)
            appendUInt32(0x0403_4b50, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(crc, to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt32(UInt32(entry.data.count), to: &archive)
            appendUInt16(UInt16(nameData.count), to: &archive)
            appendUInt16(0, to: &archive)
            archive.append(nameData)
            archive.append(entry.data)
            centralRecords.append((entry, offset, crc))
        }

        let centralOffset = UInt32(archive.count)
        for record in centralRecords {
            let nameData = Data(record.entry.path.utf8)
            appendUInt32(0x0201_4b50, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(20, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(record.crc, to: &central)
            appendUInt32(UInt32(record.entry.data.count), to: &central)
            appendUInt32(UInt32(record.entry.data.count), to: &central)
            appendUInt16(UInt16(nameData.count), to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt16(0, to: &central)
            appendUInt32(0, to: &central)
            appendUInt32(record.offset, to: &central)
            central.append(nameData)
        }
        archive.append(central)
        appendUInt32(0x0605_4b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt32(UInt32(central.count), to: &archive)
        appendUInt32(centralOffset, to: &archive)
        appendUInt16(0, to: &archive)
        return archive
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00ff))
        data.append(UInt8((value >> 8) & 0x00ff))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x0000_00ff))
        data.append(UInt8((value >> 8) & 0x0000_00ff))
        data.append(UInt8((value >> 16) & 0x0000_00ff))
        data.append(UInt8((value >> 24) & 0x0000_00ff))
    }

    private func checksum(_ data: Data) -> UInt32 {
        var value = crc32(0, nil, 0)
        data.withUnsafeBytes { raw in
            value = crc32(
                value,
                raw.bindMemory(to: Bytef.self).baseAddress,
                uInt(data.count)
            )
        }
        return UInt32(value)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ZIPFixtureEntry {
    var path: String
    var data: Data
}
