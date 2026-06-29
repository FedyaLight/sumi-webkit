import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class NativeMessagingProcessSessionTests: XCTestCase {
    func testCapabilityPolicyKeepsRealBackendDecisionPoint() {
        XCTAssertEqual(
            SumiNativeMessagingCapabilityPolicy.decide(
                SumiNativeMessagingCapabilityPolicyInput(
                    manifestRequestsNativeMessaging: true,
                    nativeMessagingPermissionGranted: true,
                    adapterAvailable: true
                )
            ),
            .supportedByAdapter
        )

        XCTAssertEqual(
            SumiNativeMessagingCapabilityPolicy.decide(
                SumiNativeMessagingCapabilityPolicyInput(
                    applicationIdentifier: "me.proton.pass.nm",
                    sourceKind: .appExtensionBundle,
                    manifestRequestsNativeMessaging: true,
                    nativeMessagingPermissionGranted: true,
                    fallbackObservedFailure: true,
                    isMacCatalystBundle: true
                )
            ),
            .fallbackObservedFailed
        )

        XCTAssertEqual(
            SumiNativeMessagingCapabilityPolicy.decide(
                SumiNativeMessagingCapabilityPolicyInput(
                    applicationIdentifier: "me.proton.pass.nm",
                    sourceKind: .appExtensionBundle,
                    manifestRequestsNativeMessaging: true,
                    nativeMessagingPermissionGranted: true,
                    privateSPIBackendAvailable: true,
                    fallbackObservedFailure: true,
                    isMacCatalystBundle: true
                )
            ),
            .supportedByPrivateSPIBackend
        )

        XCTAssertEqual(
            SumiNativeMessagingCapabilityPolicy.decide(
                SumiNativeMessagingCapabilityPolicyInput(
                    applicationIdentifier: "unsupported.example",
                    manifestRequestsNativeMessaging: true,
                    nativeMessagingPermissionGranted: true
                )
            ),
            .unsupportedNoBackend
        )
    }
}
