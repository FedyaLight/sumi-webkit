import XCTest
@testable import Sumi

final class URLBarZoomButtonVisibilityTests: XCTestCase {
    func testHiddenAtDefaultZoom() {
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: false,
                isPopoverPresented: false,
                isDefaultZoom: true
            )
        )
    }

    func testVisibleAtNonDefaultZoom() {
        XCTAssertTrue(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: false,
                isPopoverPresented: false,
                isDefaultZoom: false
            )
        )
    }

    func testVisibleWhilePopoverIsOpenAtDefaultZoom() {
        XCTAssertTrue(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: false,
                isPopoverPresented: true,
                isDefaultZoom: true
            )
        )
    }

    func testHiddenWithoutURLOrWhileEditing() {
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: false,
                isEditing: false,
                isPopoverPresented: true,
                isDefaultZoom: false
            )
        )
        XCTAssertFalse(
            URLBarZoomButtonVisibility.shouldShow(
                hasURL: true,
                isEditing: true,
                isPopoverPresented: true,
                isDefaultZoom: false
            )
        )
    }
}
