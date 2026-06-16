import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiWebExtensionCallbackErrorMapperTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        SafariExtensionWebExtensionCallbackDiagnostics.resetForTesting()
    }

    func testRelayCancelledMapsToWebExtensionContextDomainWithMessage() {
        let source = SumiNativeMessagingErrorMapper.relayError(
            code: .relayCancelled,
            diagnostic: nil
        )

        let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: source)

        XCTAssertEqual(
            mapped.domain,
            SumiWebExtensionCallbackErrorMapper.webExtensionContextErrorDomain
        )
        XCTAssertEqual(mapped.code, 1)
        XCTAssertTrue(SumiWebExtensionCallbackErrorMapper.hasSerializableMessage(mapped))
        XCTAssertEqual(
            mapped.localizedDescription,
            "Native messaging relay was cancelled."
        )
        XCTAssertNotEqual(mapped.localizedDescription, "(null)")
    }

    func testCompanionProtocolUnknownPreservesMessage() {
        let source = SumiNativeMessagingErrorMapper.relayError(
            code: .companionAppProtocolUnknown,
            diagnostic: nil
        )

        let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: source)

        XCTAssertEqual(mapped.domain, WKWebExtensionContext.errorDomain)
        XCTAssertTrue(mapped.localizedDescription.contains("Companion host application"))
    }

    func testNullLocalizedDescriptionIsReplaced() {
        let source = NSError(
            domain: SumiNativeMessagingRelay.errorDomain,
            code: SumiNativeMessagingRelay.ErrorCode.relayCancelled.rawValue,
            userInfo: [:]
        )

        let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: source)

        XCTAssertTrue(SumiWebExtensionCallbackErrorMapper.hasSerializableMessage(mapped))
        XCTAssertFalse(mapped.localizedDescription.isEmpty)
    }

    func testWrapNativeMessagingReplyHandlerInvokesExactlyOnce() {
        let expectation = expectation(description: "replyOnce")
        var callCount = 0

        let wrapped = SumiWebExtensionCallbackRelay.wrapNativeMessagingReplyHandler(
            api: .runtimeSendNativeMessage,
            extensionId: "ext-test"
        ) { _, error in
            callCount += 1
            XCTAssertNotNil(error)
            expectation.fulfill()
        }

        let source = SumiNativeMessagingErrorMapper.relayError(
            code: .relayCancelled,
            diagnostic: nil
        )
        wrapped(nil, source)
        wrapped(nil, source)

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(callCount, 1)
    }

    func testWrapCompletionHandlerMapsErrorForConnectNative() throws {
        let expectation = expectation(description: "connectCompletion")
        var mappedError: NSError?

        let wrapped = SumiWebExtensionCallbackRelay.wrapCompletionHandler(
            api: .connectNativePort,
            extensionId: "ext-test"
        ) { error in
            mappedError = error as NSError?
            expectation.fulfill()
        }

        wrapped(
            SumiNativeMessagingErrorMapper.relayError(
                code: .relayCancelled,
                diagnostic: nil
            )
        )

        wait(for: [expectation], timeout: 1)
        let error = try XCTUnwrap(mappedError)
        XCTAssertEqual(
            error.domain,
            SumiWebExtensionCallbackErrorMapper.webExtensionContextErrorDomain
        )
        XCTAssertTrue(SumiWebExtensionCallbackErrorMapper.hasSerializableMessage(error))
    }

    func testWrapCompletionHandlerSuccessPassesNilError() {
        let expectation = expectation(description: "connectSuccess")
        var receivedError: (any Error)?

        let wrapped = SumiWebExtensionCallbackRelay.wrapCompletionHandler(
            api: .connectNativePort,
            extensionId: "ext-test"
        ) { error in
            receivedError = error
            expectation.fulfill()
        }

        wrapped(nil)
        wait(for: [expectation], timeout: 1)
        XCTAssertNil(receivedError)
    }

    func testAllCallbackDiagnosticBucketsExist() {
        XCTAssertEqual(
            SafariExtensionWebExtensionCallbackDiagnosticBucket.allCases.count,
            14
        )
        XCTAssertTrue(
            SafariExtensionWebExtensionCallbackDiagnosticBucket.allCases.contains(.errorObjectNull)
        )
        XCTAssertTrue(
            SafariExtensionWebExtensionCallbackDiagnosticBucket.allCases.contains(
                .failureApiRuntimeSendNativeMessage
            )
        )
    }

    func testMessagePortDisconnectErrorUsesSerializableMessage() {
        let error = SumiNativeMessagingErrorMapper.messagePortDisconnectError(
            code: .relayCancelled,
            diagnostic: nil
        )

        XCTAssertTrue(SumiWebExtensionCallbackErrorMapper.hasSerializableMessage(error))
        XCTAssertEqual(
            error.domain,
            SumiWebExtensionCallbackErrorMapper.webExtensionContextErrorDomain
        )
    }
}
