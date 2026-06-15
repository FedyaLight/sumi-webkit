import XCTest

@testable import Sumi

/// Regression guards for the generic native-messaging adapter boundary (Cycle 12+).
@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingAdapterRegressionGuardTests: XCTestCase {
    private let adapterLayerPaths = [
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingAdapterTransport.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingProtocolAdapter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiCompanionAppResolver.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingConnection.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/CompanionApplicationMessageRouter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariApplicationIDAdapter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariCompanionStore.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnostics.swift",
    ]

    private let forbiddenCompatTokens = [
        "webkit_runtime_compat",
        "sumi_webkit_runtime_compat",
        "externally_connectable_page_bridge",
        "patchManifestForWebKit",
        "ExtensionRuntimeResources",
        "SumiExternallyConnectableUserScript",
        "ChromeMV3NativeMessaging",
    ]

    func testAdapterLayerDoesNotReferenceCompatJSShims() throws {
        let combined = try adapterLayerPaths.map { try source(named: $0) }.joined(separator: "\n")
        for token in forbiddenCompatTokens {
            XCTAssertFalse(
                combined.contains(token),
                "Adapter layer must not reference compat shim \(token)"
            )
        }
    }

    func testAdapterRegistryUsesProtocolIdentifierNotVendorBundleID() throws {
        let adapterSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingProtocolAdapter.swift"
        )
        XCTAssertTrue(adapterSource.contains("var protocolIdentifier: String"))
        XCTAssertTrue(adapterSource.contains("SumiNativeMessagingAdapterRegistry"))
        XCTAssertFalse(adapterSource.contains("bitwarden"))
        XCTAssertFalse(adapterSource.contains("1password"))
    }

    func testAdapterTransportDoesNotPatchManifestOrInjectScripts() throws {
        let transportSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingAdapterTransport.swift"
        )
        for token in forbiddenCompatTokens {
            XCTAssertFalse(transportSource.contains(token))
        }
        XCTAssertTrue(transportSource.contains("SumiNativeMessagingAdapterCapability"))
    }

    func testCleanAppexImportPathRemainsInSafariResources() throws {
        let safariResources = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariAppExtensionResources.swift"
        )
        XCTAssertTrue(safariResources.contains("WKWebExtension(appExtensionBundle:"))
        XCTAssertTrue(safariResources.contains("originalAppexBundle"))
        XCTAssertFalse(safariResources.contains("patchManifestForWebKit"))
    }

    func testLazyRuntimeProfileIsolationAndPopupAnchorGuardsRemain() throws {
        let profilesSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )
        let anchorSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift"
        )
        let loopGuardSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelayLoopGuard.swift"
        )

        XCTAssertTrue(profilesSource.contains("if forceReload {"))
        XCTAssertFalse(profilesSource.contains("await self.ensureEnabledExtensionsLoaded(for: profileId)"))
        XCTAssertTrue(anchorSource.contains("func captureActionPopupAnchor("))
        XCTAssertTrue(loopGuardSource.contains("launchSuppressed"))
        XCTAssertTrue(loopGuardSource.contains("recordSuppressedRetry"))
    }

    func testNativeMessagingNoLaunchLoopGuardWiredInRelay() throws {
        let relaySource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
        )
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingRelayLoopGuard"))
        XCTAssertTrue(relaySource.contains("recordSuppressedRetry"))
        XCTAssertTrue(relaySource.contains("launchSuppressed"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingAdapterRegistry"))
        XCTAssertTrue(relaySource.contains("CompanionApplicationMessageRouter"))
    }

    func testApplicationIdCompanionRouterDoesNotUseStandardNativeHostBackend() throws {
        let routerSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/CompanionApplicationMessageRouter.swift"
        )
        XCTAssertTrue(routerSource.contains("CompanionApplicationMessageRouter"))
        XCTAssertTrue(routerSource.contains("CompanionApplicationBackendRegistry"))
        XCTAssertTrue(routerSource.contains("CompanionApplicationMessageBackend"))
        XCTAssertTrue(routerSource.contains("isSafariContainingApplicationRequest"))
        XCTAssertFalse(routerSource.contains("StandardNativeMessagingHostBackend"))
        XCTAssertFalse(routerSource.contains("NativeMessagingHostManifestResolver"))
    }

    func testProtonSpecificLogicIsIsolatedToCompanionBackendLayer() throws {
        let allowedFiles = Set([
            "Sumi/Managers/ExtensionManager/SafariExtension/ProtonNativeMessagingIdentifiers.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/CompanionApplicationMessageRouter.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariApplicationIDAdapter.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariCompanionStore.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingClassification.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInlineUIClassificationCatalog.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionCompatibilityReport.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionManualVerificationCatalog.swift",
        ])
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") && $0.hasPrefix("Sumi/") }
        for path in candidates where allowedFiles.contains(path) == false {
            let contents = try source(named: path)
            XCTAssertFalse(
                contents.localizedCaseInsensitiveContains("proton"),
                "Unexpected Proton-specific logic in \(path)"
            )
        }
    }

    func testCompanionBackendDoesNotUseAppexNSExtensionPlugInKitManifestOrJSPatching() throws {
        let combined = try [
            "Sumi/Managers/ExtensionManager/SafariExtension/CompanionApplicationMessageRouter.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariApplicationIDAdapter.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariCompanionStore.swift",
        ].map { try source(named: $0) }.joined(separator: "\n")

        for forbidden in [
            "NSExtension",
            "PlugInKit",
            "SafariAppExtensionNativeMessagingBackend",
            "patchManifest",
            "JavaScript",
            "StandardNativeMessagingHostBackend",
            "NativeMessagingHostManifestResolver",
        ] {
            XCTAssertFalse(combined.contains(forbidden), "Forbidden token \(forbidden)")
        }
    }

    func testDiagnosticsExposeAdapterBoundaryFields() throws {
        let diagnosticsSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnostics.swift"
        )
        for symbol in [
            "adapterSelected",
            "adapterIdentifier",
            "appResolved",
            "appLaunched",
            "protocolStatus",
            "handshakeStatus",
            "autofillPathStatus",
            "failureBucket",
            "realTransportAttempted",
            "desktopResolved",
            "desktopRunning",
            "desktopLaunchAttempted",
            "desktopLaunchSuppressed",
            "biometricsStatusProbe",
            "repeatedCallCountBucket",
            "SafariExtensionNativeMessagingAdapterCompatibilityStatus",
            "SumiNativeMessagingBiometricsStatusProbe",
        ] {
            XCTAssertTrue(
                diagnosticsSource.contains(symbol),
                "Missing diagnostic symbol \(symbol)"
            )
        }
    }

    func testProbeReportIncludesAdapterCompatibilityForAllTargets() {
        let report = SafariExtensionNativeMessagingProbeBuilder.build(discovered: [])
        XCTAssertEqual(report.adapterCompatibility.count, SafariExtensionCompatibilityTargets.all.count)
        XCTAssertEqual(
            report.registeredAdapterIdentifiers,
            [
                BitwardenNativeMessagingIdentifiers.protocolIdentifier,
                StandardNativeMessagingHostBackend.backendIdentifier,
            ].sorted()
        )
        let bitwarden = report.adapterCompatibility.first { $0.targetKey == "bitwarden" }
        XCTAssertEqual(bitwarden?.adapterSelected, true)
        XCTAssertEqual(bitwarden?.adapterIdentifier, BitwardenNativeMessagingIdentifiers.protocolIdentifier)
        XCTAssertEqual(bitwarden?.protocolStatus, .notApplicable)
        XCTAssertEqual(bitwarden?.failureBucket, .extensionNotImported)
        XCTAssertEqual(bitwarden?.desktopResolved, true)
        XCTAssertEqual(bitwarden?.realTransportAttempted, false)
        XCTAssertEqual(bitwarden?.biometricsStatusProbe, .notAttempted)
        XCTAssertEqual(
            bitwarden?.repeatedCallCountBucket,
            SumiNativeMessagingRetryCountBucket.none
        )
        XCTAssertEqual(bitwarden?.launchSuppressionExpected, true)
        let raindrop = report.adapterCompatibility.first { $0.targetKey == "raindrop" }
        XCTAssertEqual(raindrop?.protocolStatus, .notApplicable)
        XCTAssertEqual(raindrop?.biometricsStatusProbe, .notApplicable)
    }

    func testDiagnosticEnrichmentMapsFailureBucketWithoutPayload() {
        let diagnostic = SafariExtensionNativeMessagingDiagnostic(
            extensionId: "ext-test",
            direction: .send,
            requestedApplicationIdentifier: "com.example.host",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            outcome: .companionAppProtocolUnknown,
            errorDomain: SumiNativeMessagingRelay.errorDomain,
            errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue,
            protocolAdapterAvailable: false
        )
        let enriched = SafariExtensionNativeMessagingDiagnosticEnrichment.enrich(diagnostic)
        XCTAssertEqual(enriched.failureBucket, .adapterUnavailable)
        XCTAssertEqual(enriched.protocolStatus, .protocolUnknown)
        XCTAssertEqual(enriched.appResolved, true)
    }

    func testDiagnosticEnrichmentMapsAdapterRegisteredRelayTimeout() {
        let adapter = BitwardenNativeMessagingAdapter()
        let diagnostic = SafariExtensionNativeMessagingDiagnostic(
            extensionId: "ext-bitwarden",
            direction: .connect,
            requestedApplicationIdentifier: "com.bitwarden.desktop",
            hostBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier,
            resolverBucket: .knownCompanionAlias,
            outcome: .companionAppProtocolUnknown,
            errorDomain: SumiNativeMessagingRelay.errorDomain,
            errorCode: SumiNativeMessagingRelay.ErrorCode.relayTimeout.rawValue,
            protocolAdapterAvailable: true,
            adapterSelected: true,
            adapterIdentifier: adapter.protocolIdentifier
        )
        let enriched = SafariExtensionNativeMessagingDiagnosticEnrichment.enrich(
            diagnostic,
            adapter: adapter,
            adapterIdentifier: adapter.protocolIdentifier
        )
        XCTAssertEqual(enriched.failureBucket, .relayTimeout)
        XCTAssertNotEqual(enriched.failureBucket, .companionAppProtocolUnknown)
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
