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
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingOneShotRelayFlow.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortConnectRelayFlow.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingConnection.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/CompanionApplicationMessageRouter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariApplicationIDAdapter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/ProtonPassSafariCompanionStore.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnostics.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingPermissionDiagnostics.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnosticEnrichment.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingRoutingProbe.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeReport.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeBuilder.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiExtensionsModule+NativeMessagingProbe.swift",
    ]

    private let diagnosticOwnerPaths = [
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnostics.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingPermissionDiagnostics.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnosticEnrichment.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingRoutingProbe.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeReport.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeBuilder.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiExtensionsModule+NativeMessagingProbe.swift",
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

    func testNativeMessagingContextTraceStaysMetadataOnly() throws {
        let managerSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager.swift"
        )
        let start = try XCTUnwrap(
            managerSource.range(of: "func traceNativeMessagingContextBinding")
        )
        let end = try XCTUnwrap(
            managerSource[start.lowerBound...].range(of: "func nativeMessagingLoadSource")
        )
        let helperSource = String(managerSource[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(helperSource.contains("nativeMessagingGranted"))
        XCTAssertTrue(helperSource.contains("unsupportedNativeMessaging"))
        XCTAssertTrue(helperSource.contains("controllerOwnsContext"))
        for forbidden in [
            "payload",
            "messageBody",
            "rawMessage",
            "absoluteString",
            "query",
            "fragment",
            "AccessToken",
            "RefreshToken",
            "clipboard",
        ] {
            XCTAssertFalse(
                helperSource.localizedCaseInsensitiveContains(forbidden),
                "Context trace must not log raw sensitive data token \(forbidden)"
            )
        }
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
        let oneShotFlowSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingOneShotRelayFlow.swift"
        )
        let portConnectFlowSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortConnectRelayFlow.swift"
        )
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingRelayLoopGuard"))
        XCTAssertTrue(relaySource.contains("recordSuppressedRetry"))
        XCTAssertTrue(relaySource.contains("launchSuppressed"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingAdapterRegistry"))
        XCTAssertTrue(relaySource.contains("CompanionApplicationMessageRouter"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingOneShotRelayFlow"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingPortConnectRelayFlow"))
        XCTAssertTrue(oneShotFlowSource.contains("trackPendingOneShot"))
        XCTAssertTrue(oneShotFlowSource.contains("untrackPendingOneShot"))
        XCTAssertTrue(oneShotFlowSource.contains("recordCompanionAppProtocolUnknown"))
        XCTAssertTrue(oneShotFlowSource.contains("recordSupportedAdapterLaunchAttempt"))
        XCTAssertTrue(portConnectFlowSource.contains("trackPortSession"))
        XCTAssertTrue(portConnectFlowSource.contains("finalizePortSession"))
        XCTAssertTrue(portConnectFlowSource.contains("recordSuppressedRetry"))
        XCTAssertTrue(portConnectFlowSource.contains("launchSuppressed"))
        XCTAssertTrue(portConnectFlowSource.contains("connectPort"))
        for forbidden in [
            "routeResolver",
            "SumiCompanionAppResolver.evaluate",
            "SumiNativeMessagingRelayPolicy",
            "evaluatePolicy(",
        ] {
            XCTAssertFalse(
                oneShotFlowSource.contains(forbidden),
                "One-shot flow owner must not decide route or policy via \(forbidden)"
            )
        }
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
            "Sumi/Managers/ExtensionManager/SafariExtension/SumiCompanionAppIdentityMetadata.swift",
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
        let diagnosticsSource = try diagnosticOwnerPaths
            .map { try source(named: $0) }
            .joined(separator: "\n")
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

    func testNativeMessagingDiagnosticsAreSplitByOwner() throws {
        let core = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnostics.swift"
        )
        XCTAssertTrue(core.contains("struct SafariExtensionNativeMessagingDiagnostic"))
        XCTAssertTrue(core.contains("enum SafariExtensionNativeMessagingErrorBucket"))
        for movedOwner in [
            "SafariExtensionNativeMessagingPermissionDiagnostics",
            "SafariExtensionNativeMessagingDiagnosticEnrichment",
            "SafariExtensionNativeMessagingRoutingProbe",
            "SafariExtensionNativeMessagingProbeBuilder",
            "extension SumiExtensionsModule",
        ] {
            XCTAssertFalse(core.contains(movedOwner), "Core diagnostics file still owns \(movedOwner)")
        }

        let enrichment = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingDiagnosticEnrichment.swift"
        )
        XCTAssertTrue(enrichment.contains("enum SafariExtensionNativeMessagingDiagnosticEnrichment"))
        XCTAssertTrue(enrichment.contains("static func failureBucket("))
        XCTAssertFalse(enrichment.contains("RuntimeDiagnostics.debug"))

        let routing = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingRoutingProbe.swift"
        )
        XCTAssertTrue(routing.contains("enum SafariExtensionNativeMessagingRoutingProbe"))
        XCTAssertTrue(routing.contains("static func sanitizedMessageShape("))
        XCTAssertTrue(routing.contains("enum SafariExtensionNativeMessagingRoutingBucket"))
        XCTAssertFalse(routing.contains("SafariExtensionNativeMessagingProbeBuilder"))

        let report = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeReport.swift"
        )
        XCTAssertTrue(report.contains("struct SafariExtensionNativeMessagingProbeReport"))
        XCTAssertTrue(report.contains("SafariExtensionNativeMessagingAdapterCompatibilityStatus"))
        XCTAssertFalse(report.contains("static func build("))

        let builder = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeBuilder.swift"
        )
        XCTAssertTrue(builder.contains("enum SafariExtensionNativeMessagingProbeBuilder"))
        XCTAssertTrue(builder.contains("static func logIfDiagnosticsEnabled"))
        XCTAssertFalse(builder.contains("extension SumiExtensionsModule"))

        let moduleAdapter = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiExtensionsModule+NativeMessagingProbe.swift"
        )
        XCTAssertTrue(moduleAdapter.contains("extension SumiExtensionsModule"))
        XCTAssertTrue(moduleAdapter.contains("safariExtensionNativeMessagingProbe()"))
    }

    func testNativeMessagingDiagnosticOwnerLoggingStaysSanitized() throws {
        let loggingSource = try [
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingPermissionDiagnostics.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingRoutingProbe.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionNativeMessagingProbeBuilder.swift",
        ].map { try source(named: $0) }.joined(separator: "\n")

        XCTAssertTrue(loggingSource.contains("extensionIdBucket("))
        XCTAssertTrue(loggingSource.contains("profileIdBucket("))
        XCTAssertTrue(loggingSource.contains("sanitizedExtensionLabel("))
        XCTAssertTrue(loggingSource.contains("sanitizedMessageShape("))
        for forbidden in [
            #"ext=\(extensionId)"#,
            #"profile=\(profileId)"#,
            #"profile=\(profileId?.uuidString"#,
            #"message=\(message)"#,
            "messageBody",
            "rawMessage",
            "payloadValue",
            "AccessToken",
            "RefreshToken",
            "clipboard",
        ] {
            XCTAssertFalse(
                loggingSource.localizedCaseInsensitiveContains(forbidden),
                "Native messaging diagnostic logs must not expose \(forbidden)"
            )
        }
    }

    func testProbeReportIncludesAdapterCompatibilityForAllTargets() {
        let report = SafariExtensionNativeMessagingProbeBuilder.build(discovered: [])
        XCTAssertEqual(report.adapterCompatibility.count, SafariExtensionCompatibilityTargets.all.count)
        XCTAssertEqual(
            report.registeredAdapterIdentifiers,
            [BitwardenNativeMessagingIdentifiers.protocolIdentifier]
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
