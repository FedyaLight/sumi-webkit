import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNormalWebViewSetupOwnerTests: XCTestCase {
    func testSetupWebViewReusesCompatibleParkedNormalWebView() async throws {
        let browserManager = BrowserManager()
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/reuse-compatible-normal-webview",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        let parkedWebView = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "TabNormalWebViewSetupOwnerTests.compatibleParkedWebView"
            )
        )

        tab._webView = nil
        tab._existingWebView = parkedWebView

        tab.setupWebView()

        XCTAssertIdentical(try XCTUnwrap(tab.existingWebView), parkedWebView)
    }

    func testInitialNormalTabRuntimeRegistrationDelaysForInitialHTTPDocuments() throws {
        let owner = TabNormalWebViewSetupOwner()

        XCTAssertTrue(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "https://example.com/start"))
            )
        )

        XCTAssertTrue(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "http://example.com/start"))
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonInitialNormalDocuments() throws {
        let owner = TabNormalWebViewSetupOwner()
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))

        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: true,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: true,
                didCreateAuxiliaryOverrideWebView: false,
                url: url
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: true,
                url: url
            )
        )
    }

    func testInitialNormalTabRuntimeRegistrationDoesNotDelayForNonWebURLs() throws {
        let owner = TabNormalWebViewSetupOwner()

        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: URL(fileURLWithPath: "/tmp/index.html")
            )
        )
        XCTAssertFalse(
            owner.shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: false,
                hasExistingWebView: false,
                didCreateAuxiliaryOverrideWebView: false,
                url: try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html"))
            )
        )
    }

    private func waitForInitialTabManagerDataLoad(on browserManager: BrowserManager) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if browserManager.tabManager.hasLoadedInitialData { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for initial tab manager data load")
    }
}
