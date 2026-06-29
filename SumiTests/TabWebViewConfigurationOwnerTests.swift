import Foundation
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewConfigurationOwnerTests: XCTestCase {
    func testInitialNormalTabRuntimeRegistrationDelaysForInitialHTTPDocuments() throws {
        let owner = TabWebViewConfigurationOwner()

        XCTAssertTrue(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "https://example.com/start"))
            )
        )

        XCTAssertTrue(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "http://example.com/start"))
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonInitialNormalDocuments() throws {
        let owner = TabWebViewConfigurationOwner()
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))

        XCTAssertFalse(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: true,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: true,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: true,
                url: url
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonWebURLs() throws {
        let owner = TabWebViewConfigurationOwner()

        XCTAssertFalse(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: URL(fileURLWithPath: "/tmp/index.html")
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html"))
            )
        )
    }
}
