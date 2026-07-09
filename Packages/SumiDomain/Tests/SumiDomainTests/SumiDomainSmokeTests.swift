import XCTest
import SumiDomain

final class SumiDomainSmokeTests: XCTestCase {
    func testPublicSuffixListLoadsBundledRules() {
        let list = SumiPublicSuffixList.bundled
        XCTAssertEqual(list.registrableDomain(forHost: "www.example.com"), "example.com")
    }

    func testSurfaceHelpersRecognizeEmptyTab() {
        XCTAssertTrue(SumiSurface.isEmptyNewTabURL(SumiSurface.emptyTabURL))
    }

    func testExtensionOwnedURLSchemes() {
        XCTAssertTrue(SumiExtensionOwnedURL.isExtensionOwnedURL(URL(string: "webkit-extension://ext-abc/")))
        XCTAssertFalse(SumiExtensionOwnedURL.isExtensionOwnedURL(URL(string: "https://example.com")))
    }

    func testShortcutPinRoleAndKeyCombination() {
        XCTAssertEqual(ShortcutPinRole.essential.rawValue, "essential")
        let combo = KeyCombination(key: "T", modifiers: [.command])
        XCTAssertEqual(combo.key, "t")
        XCTAssertEqual(combo.lookupKey, "cmd+t")
    }
}
