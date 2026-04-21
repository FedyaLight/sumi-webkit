import XCTest
@testable import Sumi

final class ZenIconLoadingTests: XCTestCase {
    func testThemePickerChromeIconsResolveFromZenReferenceBundle() {
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "plus"))
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "unpin"))
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "algorithm"))
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "sparkles"))
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "face-sun"))
        XCTAssertNotNil(SumiZenFolderIconCatalog.chromeImage(named: "moon-stars"))
    }
}
