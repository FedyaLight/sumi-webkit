import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class NativeMessagingProcessSessionTests: XCTestCase {
    func testProductNativeMessagingHandlerIsInertCompatibilityShell() throws {
        let source = try Self.source(named: "Sumi/Managers/ExtensionManager/NativeMessagingHandler.swift")

        XCTAssertTrue(source.contains("Product native messaging remains unavailable"))
        XCTAssertTrue(source.contains("ChromeMV3NativeMessagingInternalRuntime.swift"))
        XCTAssertTrue(source.contains("final class NativeMessagingHandler"))
        XCTAssertTrue(source.contains("func disconnect() {}"))

        let processCallToken = "Process" + "("
        let uncheckedSendableToken = "@unchecked" + " Sendable"
        assertSourceExcludes(
            source,
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
            context: "Product native messaging compatibility shell"
        )
    }

    func testInternalFixtureRuntimeOwnsNativeMessagingProcessLaunch() throws {
        let source = try Self.source(
            named: "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
        )

        let processInitializerToken = "Process" + "()"
        XCTAssertTrue(source.contains("ChromeMV3NativeMessagingFixtureProcess"))
        XCTAssertTrue(source.contains("private let process = \(processInitializerToken)"))
        XCTAssertTrue(source.contains("debugFixtureBuildAllowsProcessLaunch"))
        XCTAssertTrue(source.contains("processLaunchAllowedInProduct"))
        XCTAssertTrue(source.contains("nativeMessagingAvailableInProduct"))
    }

    func testProductDelegateNativeMessagingMethodsRemainBlocked() throws {
        let source = try Self.source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )

        XCTAssertTrue(source.contains("Product native messaging is unavailable"))
        XCTAssertFalse(source.contains("NativeMessagingHandler("))
        XCTAssertFalse(source.contains("NativeMessagingProcessSession"))
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
