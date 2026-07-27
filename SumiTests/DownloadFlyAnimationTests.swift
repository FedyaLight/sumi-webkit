import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class DownloadFlyAnimationTests: XCTestCase {
    private var testFileIcon: NSImage {
        NSImage(
            systemSymbolName: "doc.fill",
            accessibilityDescription: nil
        )!
    }

    func testDockFolderPathsContainOnlyDirectoryTiles() {
        let persistentOthers: [[String: Any]] = [
            [
                "tile-type": "directory-tile",
                "tile-data": [
                    "file-data": [
                        "_CFURLString": "file:///Users/example/Downloads/",
                    ],
                ],
            ],
            [
                "tile-type": "file-tile",
                "tile-data": [
                    "file-data": [
                        "_CFURLString": "file:///Users/example/report.pdf",
                    ],
                ],
            ],
            [
                "tile-type": "small-spacer-tile",
                "tile-data": ["file-label": ""],
            ],
        ]

        XCTAssertEqual(
            SystemDockDownloadDestinationChecker.folderPaths(
                from: persistentOthers
            ),
            ["/Users/example/Downloads"]
        )
    }

    func testWindowRectConvertsFromAppKitToSwiftUICoordinates() {
        let point = DownloadFlyPlacement.swiftUIPoint(
            for: CGRect(x: 100, y: 200, width: 60, height: 40),
            canvasHeight: 800
        )

        XCTAssertEqual(point, CGPoint(x: 130, y: 580))
    }

    func testCornerTargetTracksSidebarEdge() {
        let size = CGSize(width: 1200, height: 800)

        XCTAssertEqual(
            DownloadFlyPlacement.cornerTarget(
                canvasSize: size,
                sidebarPosition: .left
            ),
            CGPoint(x: 44, y: 756)
        )
        XCTAssertEqual(
            DownloadFlyPlacement.cornerTarget(
                canvasSize: size,
                sidebarPosition: .right
            ),
            CGPoint(x: 1156, y: 756)
        )
    }

    func testArcLiftsFileAboveBothEndpoints() {
        let start = CGPoint(x: 700, y: 360)
        let end = CGPoint(x: 60, y: 740)

        let arc = DownloadFlyPlacement.arc(
            start: start,
            end: end
        )
        let midpoint = arc.point(at: 0.5)

        XCTAssertEqual(arc.departureControl.x, start.x)
        XCTAssertEqual(arc.arrivalControl.x, end.x)
        XCTAssertEqual(arc.departureControl.y, arc.arrivalControl.y)
        XCTAssertLessThan(midpoint.y, start.y)
        XCTAssertLessThan(midpoint.y, end.y)
        XCTAssertEqual(midpoint.y, start.y - 144, accuracy: 0.001)
    }

    func testArcKeepsModestLiftForShortFlights() {
        let start = CGPoint(x: 300, y: 300)
        let end = CGPoint(x: 380, y: 340)

        let arc = DownloadFlyPlacement.arc(
            start: start,
            end: end
        )

        XCTAssertEqual(arc.point(at: 0.5).y, 244, accuracy: 0.001)
    }

    func testArcEntersTargetVerticallyFromAbove() {
        let end = CGPoint(x: 60, y: 740)
        let arc = DownloadFlyPlacement.arc(
            start: CGPoint(x: 700, y: 360),
            end: end
        )
        let nearEnd = arc.point(at: 0.99)

        XCTAssertLessThan(nearEnd.y, end.y)
        XCTAssertLessThan(
            abs(end.x - nearEnd.x),
            abs(end.y - nearEnd.y) * 0.05
        )
    }

    func testFlyingGlyphMovesAfterItIsMounted() async throws {
        let host = NSHostingView(
            rootView: DownloadFlyingGlyph(
                presentation: DownloadFlyPresentation(
                    id: UUID(),
                    arc: DownloadFlyPlacement.arc(
                        start: CGPoint(x: 50, y: 320),
                        end: CGPoint(x: 350, y: 320)
                    ),
                    icon: testFileIcon
                ),
                reducesMotion: false
            )
        )
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        try await Task.sleep(for: .milliseconds(60))
        let initialCenter = try visiblePixelCenter(in: host)
        try await Task.sleep(for: .milliseconds(240))
        let animatedCenter = try visiblePixelCenter(in: host)

        XCTAssertGreaterThan(
            animatedCenter.x - initialCenter.x,
            40,
            "The download glyph remained at its initial position"
        )
    }

    private func visiblePixelCenter(in host: NSView) throws -> CGPoint {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: bitmap)

        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        var count: CGFloat = 0
        for row in 0 ..< bitmap.pixelsHigh {
            for column in 0 ..< bitmap.pixelsWide {
                guard (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.05 else {
                    continue
                }
                totalX += CGFloat(column)
                totalY += CGFloat(row)
                count += 1
            }
        }

        XCTAssertGreaterThan(count, 0)
        return CGPoint(x: totalX / count, y: totalY / count)
    }
}
