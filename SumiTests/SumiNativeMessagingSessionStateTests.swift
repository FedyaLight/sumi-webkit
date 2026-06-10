import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingSessionStateTests: XCTestCase {
    func testUnknownProtocolInitialThenSuppressed() {
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: UUID(),
            extensionId: "ext-1",
            applicationIdentifier: "com.example.host"
        )

        let initial = loopGuard.sessionState(
            policyDenial: nil,
            profileRuntimeLoaded: true,
            evaluation: .appFoundButProtocolUnknown(
                detail(host: "com.example.host")
            ),
            hostBundleIdentifier: "com.example.host",
            key: key
        )
        XCTAssertEqual(initial, .protocolAdapterUnavailable)

        loopGuard.recordCompanionAppProtocolUnknown(key: key, launchAttempted: false)
        let suppressed = loopGuard.sessionState(
            policyDenial: nil,
            profileRuntimeLoaded: true,
            evaluation: .launchSuppressed(detail(host: "com.example.host")),
            hostBundleIdentifier: "com.example.host",
            key: key
        )
        XCTAssertEqual(suppressed, .unknownProtocolSuppressed)
    }

    func testDiagnosticCoalescerEmitsDetailedThenSummarized() {
        var styles: [SumiNativeMessagingDiagnosticLogStyle] = []
        let coalescer = SumiNativeMessagingDiagnosticCoalescer { _, style in
            styles.append(style)
        }

        let diagnostic = SafariExtensionNativeMessagingDiagnostic(
            extensionId: "ext-1",
            direction: .send,
            requestedApplicationIdentifier: "com.example.host",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: nil,
            outcome: .companionAppProtocolUnknown,
            errorDomain: SumiNativeMessagingRelay.errorDomain,
            errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue,
            retryCountBucket: .none
        )

        coalescer.record(diagnostic)
        coalescer.record(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: diagnostic.extensionId,
                direction: diagnostic.direction,
                requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
                hostBundleIdentifier: diagnostic.hostBundleIdentifier,
                resolverBucket: diagnostic.resolverBucket,
                outcome: .launchSuppressed,
                errorDomain: diagnostic.errorDomain,
                errorCode: diagnostic.errorCode,
                launchSuppressed: true,
                retryCountBucket: .first
            )
        )
        coalescer.record(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: diagnostic.extensionId,
                direction: diagnostic.direction,
                requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
                hostBundleIdentifier: diagnostic.hostBundleIdentifier,
                resolverBucket: diagnostic.resolverBucket,
                outcome: .launchSuppressed,
                errorDomain: diagnostic.errorDomain,
                errorCode: diagnostic.errorCode,
                launchSuppressed: true,
                retryCountBucket: .first
            )
        )

        XCTAssertEqual(styles.count, 2)
        XCTAssertEqual(styles.first, .detailed)
        if case .summarized(let repeatCount, let bucket) = styles.last {
            XCTAssertEqual(repeatCount, 2)
            XCTAssertEqual(bucket, .first)
        } else {
            XCTFail("Expected summarized log style")
        }
    }

    private func detail(host: String) -> SumiCompanionAppResolutionDetail {
        SumiCompanionAppResolutionDetail(
            requestedApplicationIdentifier: host,
            resolvedBundleIdentifier: host,
            isContainingApp: true,
            resolutionSource: .containingAppOfImportedAppex,
            appInstalled: true,
            protocolAdapterAvailable: false,
            launchAllowed: false,
            launchDecision: .suppressedNoProtocolAdapter
        )
    }
}
