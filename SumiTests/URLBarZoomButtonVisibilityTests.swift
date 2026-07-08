@testable import Sumi
import XCTest

final class URLBarZoomButtonVisibilityTests: XCTestCase {
    func testHiddenAtDefaultZoom() {
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: false,
                isDefaultZoom: true
            )
        )
    }

    func testVisibleAtNonDefaultZoom() {
        XCTAssertTrue(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: false,
                isDefaultZoom: false
            )
        )
    }

    func testHiddenWithoutURLOrWhileEditing() {
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: false,
                isEditing: false,
                isDefaultZoom: false
            )
        )
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: true,
                isDefaultZoom: false
            )
        )
    }
}
