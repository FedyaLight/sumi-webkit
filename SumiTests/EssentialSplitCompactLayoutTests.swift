import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class EssentialSplitCompactLayoutTests: XCTestCase {
    func testThreeMembersUseTwoLeftCellsAndOneFullHeightRightCell() {
        let rects = SplitTileGeometry.resolve(
            in: CGSize(width: 100, height: 80),
            count: 3,
            thickness: 2
        ).contentRects

        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 49, height: 39))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 41, width: 49, height: 39))
        XCTAssertEqual(rects[2], CGRect(x: 51, y: 0, width: 49, height: 80))
    }

    func testFourMembersUseStableRowMajorGrid() {
        let rects = SplitTileGeometry.resolve(
            in: CGSize(width: 100, height: 80),
            count: 4,
            thickness: 2
        ).contentRects

        XCTAssertEqual(rects, [
            CGRect(x: 0, y: 0, width: 49, height: 39),
            CGRect(x: 51, y: 0, width: 49, height: 39),
            CGRect(x: 0, y: 41, width: 49, height: 39),
            CGRect(x: 51, y: 41, width: 49, height: 39),
        ])
    }

    func testThreeMemberTileUsesOneSharedOuterShapeAndInternalDividers() {
        let geometry = SplitTileGeometry.resolve(
            in: CGSize(width: 100, height: 80),
            count: 3,
            thickness: 2
        )

        XCTAssertEqual(
            geometry.outerRect,
            CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        XCTAssertEqual(geometry.dividerRects, [
            CGRect(x: 49, y: 0, width: 2, height: 80),
            CGRect(x: 0, y: 39, width: 51, height: 2),
        ])
    }

    func testActiveChromeContinuouslyFillsDividersThroughOuterRing() throws {
        let size = CGSize(width: 100, height: 80)
        let transparentIcon = NSImage(size: NSSize(width: 16, height: 16))
        let view = EssentialSplitCompactVisual(
            members: (0..<4).map { _ in
                EssentialSplitTileMemberPresentation(
                    icon: Image(nsImage: transparentIcon),
                    glyphText: nil,
                    systemImageName: nil,
                    accentColor: .red,
                    title: "Tab"
                )
            },
            isGroupActive: true,
            activeBackground: .black
        )
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        representation.size = size
        host.cacheDisplay(in: host.bounds, to: representation)
        let scale = CGFloat(representation.pixelsWide) / size.width
        let chromePoints = [
            CGPoint(x: 50, y: 1),
            CGPoint(x: 50, y: 20),
            CGPoint(x: 50, y: 40),
            CGPoint(x: 50, y: 60),
            CGPoint(x: 50, y: 79),
            CGPoint(x: 1, y: 40),
            CGPoint(x: 25, y: 40),
            CGPoint(x: 75, y: 40),
            CGPoint(x: 99, y: 40),
        ]
        let missingPoints = chromePoints.filter { point in
            guard let color = representation.colorAt(
                x: min(
                    representation.pixelsWide - 1,
                    Int((point.x * scale).rounded())
                ),
                y: min(
                    representation.pixelsHigh - 1,
                    Int((point.y * scale).rounded())
                )
            ) else { return true }
            return color.redComponent < 0.75
                || color.greenComponent > 0.25
                || color.blueComponent > 0.25
        }

        XCTAssertTrue(
            missingPoints.isEmpty,
            "Chrome has unfilled points at \(missingPoints)"
        )
    }
}
