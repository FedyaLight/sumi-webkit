import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebKitUIDelegateOwnerTests: XCTestCase {
    func testPopupOriginHelperClassifiesExtensionOwnedNavigations() {
        let extensionURL = URL(string: "safari-web-extension://extension-id/popup.html")!
        let webURL = URL(string: "https://example.com/account")!
        let otherExtensionURL = URL(string: "webkit-extension://other-id/page.html")!
        let fileURL = URL(fileURLWithPath: "/tmp/example.html")

        XCTAssertTrue(
            SumiPopupNavigationOrigin.isExtensionOriginatedPopupNavigation(
                sourceURL: extensionURL,
                requestURL: nil
            )
        )
        XCTAssertTrue(
            SumiPopupNavigationOrigin.isExtensionOriginatedPopupNavigation(
                sourceURL: nil,
                requestURL: otherExtensionURL
            )
        )
        XCTAssertTrue(
            SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: extensionURL,
                requestURL: webURL
            )
        )
        XCTAssertFalse(
            SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: nil,
                requestURL: webURL
            )
        )
        XCTAssertFalse(
            SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: extensionURL,
                requestURL: otherExtensionURL
            )
        )
        XCTAssertFalse(
            SumiPopupNavigationOrigin.isExtensionOriginatedExternalPopupNavigation(
                sourceURL: extensionURL,
                requestURL: fileURL
            )
        )
    }

    func testJavaScriptDialogNoWindowFallbacksCompleteWithExistingDefaults() {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let owner = tab.webKitUIDelegateOwner
        let webView = WKWebView(frame: .zero)
        let frame = TabWebKitUIDelegateOwnerFrameInfoMock().frameInfo
        var didAlertComplete = false
        var confirmDecision: Bool?
        var didPromptComplete = false
        var promptDecision: String?

        owner.webView(
            webView,
            runJavaScriptAlertPanelWithMessage: "alert",
            initiatedByFrame: frame
        ) {
            didAlertComplete = true
        }
        owner.webView(
            webView,
            runJavaScriptConfirmPanelWithMessage: "confirm",
            initiatedByFrame: frame
        ) { decision in
            confirmDecision = decision
        }
        owner.webView(
            webView,
            runJavaScriptTextInputPanelWithPrompt: "prompt",
            defaultText: "default",
            initiatedByFrame: frame
        ) { decision in
            didPromptComplete = true
            promptDecision = decision
        }

        XCTAssertTrue(didAlertComplete)
        XCTAssertEqual(confirmDecision, false)
        XCTAssertTrue(didPromptComplete)
        XCTAssertNil(promptDecision)
    }

    func testNormalTabWebViewPreparationInstallsDedicatedUIDelegateOwner() {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        tab.configureNormalTabWebView(webView, reason: "TabWebKitUIDelegateOwnerTests")

        XCTAssertTrue((webView.uiDelegate as? TabWebKitUIDelegateOwner) === tab.webKitUIDelegateOwner)
    }
}

private final class TabWebKitUIDelegateOwnerFrameInfoMock: NSObject {
    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}
