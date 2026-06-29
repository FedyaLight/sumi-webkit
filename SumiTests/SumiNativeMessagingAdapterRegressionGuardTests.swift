import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingAdapterRegressionGuardTests: XCTestCase {
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

    func testDiagnosticEnrichmentMapsFailureBucketWithoutPayload() throws {
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
        XCTAssertTrue(try XCTUnwrap(enriched.appResolved))
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
}
