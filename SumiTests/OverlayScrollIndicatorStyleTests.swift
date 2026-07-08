import AppKit
import XCTest
@testable import Sumi

final class OverlayScrollIndicatorStyleTests: XCTestCase {
    func testSharedStyleUsesMidGrayThumbColor() {
        let color = OverlayScrollIndicatorStyle.thumbColor.usingColorSpace(.sRGB)
        XCTAssertNotNil(color)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.50, accuracy: 0.001)
        XCTAssertEqual(green, 0.50, accuracy: 0.001)
        XCTAssertEqual(blue, 0.50, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(OverlayScrollIndicatorStyle.thumbOpacity, 0.40, accuracy: 0.001)
    }

    func testSidebarLayoutAliasesSharedStyleMetrics() {
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.thumbWidth,
            OverlayScrollIndicatorStyle.thumbWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.expandedThumbWidth,
            OverlayScrollIndicatorStyle.expandedThumbWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.thumbOpacity,
            OverlayScrollIndicatorStyle.thumbOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.visibleDuration,
            OverlayScrollIndicatorStyle.visibleDuration,
            accuracy: 0.001
        )
    }

    @MainActor
    func testNativeScrollbarHideUserScriptSuppressesWebKitScroller() {
        let source = SumiNativeScrollbarHideUserScript.makeSource()
        XCTAssertTrue(source.contains("scrollbar-width: none"))
        XCTAssertTrue(source.contains("::-webkit-scrollbar"))
        XCTAssertTrue(source.contains("display: none"))
        XCTAssertFalse(source.contains("createElement('div')"))
    }
}
