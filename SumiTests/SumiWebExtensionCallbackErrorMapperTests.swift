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
        let cases: [(ExtensionManagerCallbackError, Int, String)] = [
            (.noPopupPopover, 1, "No popup popover is available"),
            (.extensionIdentifierUnavailable, 2, "No extension identifier is available"),
            (.extensionManagerUnavailable, 3, "Extension manager is unavailable"),
            (.requestedTabBrowserManagerUnavailable, 3, "Browser manager is unavailable"),
            (.browserManagerUnavailable, 4, "Browser manager is unavailable"),
            (.newWindowUnavailable, 5, "Sumi could not resolve the new window"),
            (.extensionExternalTabUnavailable, 6, "Sumi could not open the extension external tab"),
            (.extensionPopupWindowUnavailable, 6, "Sumi could not open the extension popup window"),
            (.optionsPageNotFound, 6, "No options page was found for this extension"),
            (.privateWindowsUnsupported, 7, "Sumi does not support private extension windows without an isolated private extension runtime"),
            (.optionsURLOutsideExtensionDirectory, 7, "Options URL outside extension directory"),
        ]

        for (callbackError, code, message) in cases {
            let error = callbackError.nsError()

            XCTAssertEqual(error.domain, ExtensionManagerCallbackError.domain)
            XCTAssertEqual(error.code, code)
            XCTAssertEqual(error.localizedDescription, message)
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
        let cases: [(ExtensionBridgeAdapterCallbackError, String, Int, String)] = [
            (
                .windowUnavailable(operation: .focus),
                "ExtensionWindowAdapter",
                1,
                "Window is no longer available"
            ),
            (
                .windowUnavailable(operation: .setWindowState),
                "ExtensionWindowAdapter",
                2,
                "Window is no longer available"
            ),
            (
                .windowUnavailable(operation: .setFrame),
                "ExtensionWindowAdapter",
                3,
                "Window is no longer available"
            ),
            (
                .windowUnavailable(operation: .close),
                "ExtensionWindowAdapter",
                4,
                "Window is no longer available"
            ),
            (
                .miniWindowUnavailable(operation: .close),
                "ExtensionMiniWindowAdapter",
                1,
                "Mini-window is no longer available"
            ),
            (
                .miniWindowUnavailable(operation: .setWindowState),
                "ExtensionMiniWindowAdapter",
                2,
                "Mini-window is no longer available"
            ),
            (
                .miniWindowUnavailable(operation: .setFrame),
                "ExtensionMiniWindowAdapter",
                3,
                "Mini-window is no longer available"
            ),
            (
                .tabUnavailable,
                "ExtensionTabAdapter",
                1,
                "Tab is no longer available"
            ),
            (
                .tabWebViewUnavailable,
                "ExtensionTabAdapter",
                2,
                "No live web view is available for this tab"
            ),
            (
                .tabUnavailableUntilReload,
                "ExtensionTabAdapter",
                3,
                "Tab is not available to extensions until it is reloaded or navigates to a new document"
            ),
            (
                .tabWindowUnavailable,
                "ExtensionTabAdapter",
                4,
                "No browser window is available for this tab"
            ),
        ]

        for (callbackError, domain, code, message) in cases {
            let error = callbackError.nsError()

            XCTAssertEqual(error.domain, domain)
            XCTAssertEqual(error.code, code)
            XCTAssertEqual(error.localizedDescription, message)
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
