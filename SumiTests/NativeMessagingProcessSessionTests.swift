import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class NativeMessagingProcessSessionTests: XCTestCase {
    func testProductNativeMessagingUsesSafariWebKitFoundation() throws {
        let relaySource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
        )
        let portSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift"
        )
        let delegateSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )

        XCTAssertTrue(relaySource.contains("SumiNativeMessagingRelay"))
        XCTAssertTrue(relaySource.contains("SumiNativeMessagingConnection"))
        XCTAssertFalse(relaySource.contains("ChromeMV3NativeMessagingInternalRuntime"))
        XCTAssertTrue(portSource.contains("WKWebExtension.MessagePort"))
        XCTAssertTrue(delegateSource.contains("sendMessage message: Any"))
        XCTAssertTrue(delegateSource.contains("connectUsing port: WKWebExtension.MessagePort"))
        XCTAssertTrue(delegateSource.contains("nativeMessagingRelay.handleSendMessage"))
        XCTAssertTrue(delegateSource.contains("nativeMessagingRelay.handleConnect"))
        XCTAssertFalse(delegateSource.contains("safariNativeMessagingHost.handleSendMessage"))
        XCTAssertFalse(delegateSource.contains("safariNativeMessagingHost.handleConnect"))

        let processCallToken = "Process" + "("
        let uncheckedSendableToken = "@unchecked" + " Sendable"
        assertSourceExcludes(
            relaySource + portSource,
            [
                processCallToken,
                "NativeMessagingProcessSession",
                "DispatchSource",
                "DispatchSourceTimer",
                "allowed_origins",
                "Library/Application Support",
                "readDataToEndOfFile",
                "waitUntilExit",
                uncheckedSendableToken,
            ],
            context: "Safari native messaging foundation"
        )
    }

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

    private static func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertSourceExcludes(
        _ source: String,
        _ forbidden: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for token in forbidden {
            XCTAssertFalse(
                source.contains(token),
                "\(context) should not contain \(token)",
                file: file,
                line: line
            )
        }
    }
}
