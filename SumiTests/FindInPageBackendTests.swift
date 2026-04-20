import XCTest
@testable import Sumi

@MainActor
final class FindInPageBackendTests: XCTestCase {

    func test_WKFindOptions_bitLayout_matches_expected_powers_of_two() {
        XCTAssertEqual(_WKFindOptions.caseInsensitive.rawValue, 1 << 0)
        XCTAssertEqual(_WKFindOptions.atWordStarts.rawValue, 1 << 1)
        XCTAssertEqual(_WKFindOptions.treatMedialCapitalAsWordStart.rawValue, 1 << 2)
        XCTAssertEqual(_WKFindOptions.backwards.rawValue, 1 << 3)
        XCTAssertEqual(_WKFindOptions.wrapAround.rawValue, 1 << 4)
        XCTAssertEqual(_WKFindOptions.showOverlay.rawValue, 1 << 5)
        XCTAssertEqual(_WKFindOptions.showFindIndicator.rawValue, 1 << 6)
        XCTAssertEqual(_WKFindOptions.showHighlight.rawValue, 1 << 7)
        XCTAssertEqual(_WKFindOptions.noIndexChange.rawValue, 1 << 8)
        XCTAssertEqual(_WKFindOptions.determineMatchIndex.rawValue, 1 << 9)
    }

    func test_sameDocumentNavigation_closesFindOnlyForPushAndPop() {
        XCTAssertFalse(SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: 0))
        XCTAssertTrue(SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: 1))
        XCTAssertFalse(SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: 2))
        XCTAssertTrue(SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: 3))
        XCTAssertFalse(SumiSameDocumentNavigationType.shouldCloseFindInPage(forWebKitSameDocumentNavigationRaw: 99))
    }

    func test_findInPageExtension_didStartNavigation_closesVisibleSession() {
        let ext = FindInPageTabExtension()
        ext.model.show()
        ext.model.find("needle")
        XCTAssertTrue(ext.model.isVisible)

        ext.didStartNavigation()

        XCTAssertFalse(ext.model.isVisible)
    }

    func test_findInPageExtension_didSameDocumentNavigation_closesVisibleSession() {
        let ext = FindInPageTabExtension()
        ext.model.show()
        XCTAssertTrue(ext.model.isVisible)

        ext.didSameDocumentNavigation()

        XCTAssertFalse(ext.model.isVisible)
    }
}
