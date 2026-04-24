import Navigation
import XCTest
@testable import Sumi

@MainActor
final class FindInPageBackendTests: XCTestCase {

    func test_WKFindOptions_bitLayout_matches_expected_powers_of_two() {
        XCTAssertEqual(_WKFindOptions.caseInsensitive.rawValue, 1 << 0)
        XCTAssertEqual(_WKFindOptions.backwards.rawValue, 1 << 3)
        XCTAssertEqual(_WKFindOptions.wrapAround.rawValue, 1 << 4)
        XCTAssertEqual(_WKFindOptions.showOverlay.rawValue, 1 << 5)
        XCTAssertEqual(_WKFindOptions.showFindIndicator.rawValue, 1 << 6)
        XCTAssertEqual(_WKFindOptions.noIndexChange.rawValue, 1 << 8)
        XCTAssertEqual(_WKFindOptions.determineMatchIndex.rawValue, 1 << 9)
    }

    func test_sameDocumentNavigation_closesFindOnlyForPushAndPop() {
        let ext = FindInPageTabExtension()
        let navigation = Navigation(
            identity: .expected,
            responders: ResponderChain(),
            state: .started,
            isCurrent: true
        )

        ext.model.show()
        ext.navigation(navigation, didSameDocumentNavigationOf: .anchorNavigation)
        XCTAssertTrue(ext.model.isVisible)

        ext.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePush)
        XCTAssertFalse(ext.model.isVisible)

        ext.model.show()
        ext.navigation(navigation, didSameDocumentNavigationOf: .sessionStateReplace)
        XCTAssertTrue(ext.model.isVisible)

        ext.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePop)
        XCTAssertFalse(ext.model.isVisible)
    }

    func test_findInPageExtension_didStartResponder_closesVisibleSession() {
        let ext = FindInPageTabExtension()
        ext.model.show()
        ext.model.find("needle")
        XCTAssertTrue(ext.model.isVisible)

        ext.didStart(
            Navigation(
                identity: .expected,
                responders: ResponderChain(),
                state: .started,
                isCurrent: true
            )
        )

        XCTAssertFalse(ext.model.isVisible)
    }

    func test_findInPageExtension_sessionStatePush_closesVisibleSession() {
        let ext = FindInPageTabExtension()
        let navigation = Navigation(
            identity: .expected,
            responders: ResponderChain(),
            state: .started,
            isCurrent: true
        )
        ext.model.show()
        XCTAssertTrue(ext.model.isVisible)

        ext.navigation(navigation, didSameDocumentNavigationOf: .sessionStatePush)

        XCTAssertFalse(ext.model.isVisible)
    }
}
