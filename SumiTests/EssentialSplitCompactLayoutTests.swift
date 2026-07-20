import XCTest

@testable import Sumi

final class EssentialSplitCompactLayoutTests: XCTestCase {
    func testThreeMembersUseTwoLeftCellsAndOneFullHeightRightCell() {
        let rects = EssentialSplitCompactLayout.rects(
            in: CGSize(width: 100, height: 80),
            count: 3,
            gap: 2
        )

        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 49, height: 39))
        XCTAssertEqual(rects[1], CGRect(x: 0, y: 41, width: 49, height: 39))
        XCTAssertEqual(rects[2], CGRect(x: 51, y: 0, width: 49, height: 80))
    }

    func testFourMembersUseStableRowMajorGrid() {
        let rects = EssentialSplitCompactLayout.rects(
            in: CGSize(width: 100, height: 80),
            count: 4,
            gap: 2
        )

        XCTAssertEqual(rects, [
            CGRect(x: 0, y: 0, width: 49, height: 39),
            CGRect(x: 51, y: 0, width: 49, height: 39),
            CGRect(x: 0, y: 41, width: 49, height: 39),
            CGRect(x: 51, y: 41, width: 49, height: 39),
        ])
    }

    func testThreeMemberTileUsesOneSharedOuterShapeAndInternalDividers() {
        let geometry = EssentialSplitCompactChromeGeometry.resolve(
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

    func testAccentMeshAnchorsEachColorAtItsMemberCenter() {
        for count in 2...4 {
            let size = CGSize(width: 100, height: 80)
            let rects = EssentialSplitCompactLayout.rects(
                in: size,
                count: count,
                gap: 2
            )
            let mesh = EssentialSplitAccentMesh.resolve(
                in: size,
                memberRects: rects
            )

            for (memberIndex, rect) in rects.enumerated() {
                let expectedPoint = SIMD2<Float>(
                    Float(rect.midX / size.width),
                    Float(rect.midY / size.height)
                )
                guard let meshIndex = mesh.points.firstIndex(where: {
                    abs($0.x - expectedPoint.x) < 0.0001
                        && abs($0.y - expectedPoint.y) < 0.0001
                }) else {
                    XCTFail("Missing member-center mesh point")
                    continue
                }
                XCTAssertEqual(
                    mesh.colorIndices[meshIndex],
                    memberIndex,
                    "Member \(memberIndex) must own its geometric color anchor"
                )
            }
        }
    }
}
