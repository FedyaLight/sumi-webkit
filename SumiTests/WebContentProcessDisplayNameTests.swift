import WebKit
import XCTest

@testable import Sumi

final class WebContentProcessDisplayNameTests: XCTestCase {
    func testAuxiliarySurfaceDisplayNameMapping() {
        XCTAssertEqual(
            BrowserConfigurationAuxiliarySurface.faviconDownload.sumiWebContentProcessDisplayName,
            "Sumi Web Content (Favicon)"
        )
        XCTAssertEqual(
            BrowserConfigurationAuxiliarySurface.glance.sumiWebContentProcessDisplayName,
            "Sumi Web Content (Peek)"
        )
        XCTAssertEqual(
            BrowserConfigurationAuxiliarySurface.miniWindow.sumiWebContentProcessDisplayName,
            "Sumi Web Content (Mini Window)"
        )
        XCTAssertEqual(
            BrowserConfigurationAuxiliarySurface.extensionOptions.sumiWebContentProcessDisplayName,
            "Sumi Web Content (Extension Options)"
        )
    }

    func testProviderStableRoleLabels() {
        XCTAssertEqual(WebContentProcessDisplayNameProvider.normalTab, "Sumi Web Content")
        XCTAssertEqual(WebContentProcessDisplayNameProvider.popup, "Sumi Web Content (Popup)")
        XCTAssertEqual(
            WebContentProcessDisplayNameProvider.auxiliaryTemplate,
            "Sumi Web Content (Auxiliary)"
        )
    }

    func testApplyDoesNotCrashOnConfiguration() {
        let configuration = WKWebViewConfiguration()
        WebContentProcessDisplayNameProvider.apply("Sumi Web Content", to: configuration)
    }
}
