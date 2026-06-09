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
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleSendMessage"))
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleConnect"))

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
