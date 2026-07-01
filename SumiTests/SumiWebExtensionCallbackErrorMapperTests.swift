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

    func testExtensionManagerCallbackErrorsPreserveLegacyNSErrorShape() {
        let cases: [ExtensionManagerCallbackErrorCase] = [
            .init(callbackError: .noPopupPopover, code: 1, message: "No popup popover is available"),
            .init(callbackError: .extensionIdentifierUnavailable, code: 2, message: "No extension identifier is available"),
            .init(callbackError: .extensionManagerUnavailable, code: 3, message: "Extension manager is unavailable"),
            .init(callbackError: .requestedTabBrowserManagerUnavailable, code: 3, message: "Browser manager is unavailable"),
            .init(callbackError: .browserManagerUnavailable, code: 4, message: "Browser manager is unavailable"),
            .init(callbackError: .newWindowUnavailable, code: 5, message: "Sumi could not resolve the new window"),
            .init(callbackError: .extensionExternalTabUnavailable, code: 6, message: "Sumi could not open the extension external tab"),
            .init(callbackError: .extensionPopupWindowUnavailable, code: 6, message: "Sumi could not open the extension popup window"),
            .init(callbackError: .optionsPageNotFound, code: 6, message: "No options page was found for this extension"),
            .init(
                callbackError: .privateWindowsUnsupported,
                code: 7,
                message: "Sumi does not support private extension windows without an isolated private extension runtime"
            ),
            .init(callbackError: .optionsURLOutsideExtensionDirectory, code: 7, message: "Options URL outside extension directory"),
        ]

        for testCase in cases {
            let error = testCase.callbackError.nsError()

            XCTAssertEqual(error.domain, ExtensionManagerCallbackError.domain)
            XCTAssertEqual(error.code, testCase.code)
            XCTAssertEqual(error.localizedDescription, testCase.message)
        }
    }

    func testExtensionManagerActionPopupAnchorErrorPreservesDiagnostics() {
        let error = ExtensionManagerCallbackError
            .actionPopupAnchorUnavailable(anchorSource: "stale")
            .nsError()

        XCTAssertEqual(error.domain, ExtensionManagerCallbackError.domain)
        XCTAssertEqual(error.code, 2)
        XCTAssertEqual(error.localizedDescription, "No URL-hub anchor is available for the extension action popup")
        XCTAssertEqual(error.userInfo["anchorSource"] as? String, "stale")
    }

    func testExtensionBridgeAdapterErrorsPreserveLegacyNSErrorShape() {
        let cases: [ExtensionBridgeAdapterErrorCase] = [
            .init(
                callbackError: .windowUnavailable(operation: .focus),
                domain: "ExtensionWindowAdapter",
                code: 1,
                message: "Window is no longer available"
            ),
            .init(
                callbackError: .windowUnavailable(operation: .setWindowState),
                domain: "ExtensionWindowAdapter",
                code: 2,
                message: "Window is no longer available"
            ),
            .init(callbackError: .windowUnavailable(operation: .setFrame), domain: "ExtensionWindowAdapter", code: 3, message: "Window is no longer available"),
            .init(callbackError: .windowUnavailable(operation: .close), domain: "ExtensionWindowAdapter", code: 4, message: "Window is no longer available"),
            .init(
                callbackError: .miniWindowUnavailable(operation: .close),
                domain: "ExtensionMiniWindowAdapter",
                code: 1,
                message: "Mini-window is no longer available"
            ),
            .init(
                callbackError: .miniWindowUnavailable(operation: .setWindowState),
                domain: "ExtensionMiniWindowAdapter",
                code: 2,
                message: "Mini-window is no longer available"
            ),
            .init(
                callbackError: .miniWindowUnavailable(operation: .setFrame),
                domain: "ExtensionMiniWindowAdapter",
                code: 3,
                message: "Mini-window is no longer available"
            ),
            .init(callbackError: .tabUnavailable, domain: "ExtensionTabAdapter", code: 1, message: "Tab is no longer available"),
            .init(callbackError: .tabWebViewUnavailable, domain: "ExtensionTabAdapter", code: 2, message: "No live web view is available for this tab"),
            .init(
                callbackError: .tabUnavailableUntilReload,
                domain: "ExtensionTabAdapter",
                code: 3,
                message: "Tab is not available to extensions until it is reloaded or navigates to a new document"
            ),
            .init(callbackError: .tabWindowUnavailable, domain: "ExtensionTabAdapter", code: 4, message: "No browser window is available for this tab"),
        ]

        for testCase in cases {
            let error = testCase.callbackError.nsError()

            XCTAssertEqual(error.domain, testCase.domain)
            XCTAssertEqual(error.code, testCase.code)
            XCTAssertEqual(error.localizedDescription, testCase.message)
        }
    }

    func testExtensionManagerCallbackErrorMapsWithStableMessage() {
        let source = ExtensionManagerCallbackError.extensionPopupWindowUnavailable.nsError()

        let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: source)

        XCTAssertEqual(
            mapped.domain,
            SumiWebExtensionCallbackErrorMapper.webExtensionContextErrorDomain
        )
        XCTAssertEqual(mapped.localizedDescription, "Sumi could not open the extension popup window")
        XCTAssertEqual(
            mapped.userInfo[SumiWebExtensionCallbackErrorMapper.underlyingDomainUserInfoKey] as? String,
            ExtensionManagerCallbackError.domain
        )
        XCTAssertEqual(
            mapped.userInfo[SumiWebExtensionCallbackErrorMapper.underlyingCodeUserInfoKey] as? Int,
            6
        )
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

private struct ExtensionManagerCallbackErrorCase {
    let callbackError: ExtensionManagerCallbackError
    let code: Int
    let message: String
}

private struct ExtensionBridgeAdapterErrorCase {
    let callbackError: ExtensionBridgeAdapterCallbackError
    let domain: String
    let code: Int
    let message: String
}
