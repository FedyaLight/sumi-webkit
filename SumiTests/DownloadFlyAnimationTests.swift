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

    func testFlightCurveSpansTheFullRangeMonotonically() {
        XCTAssertEqual(DownloadFlyCurve.flightProgress(atTime: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(DownloadFlyCurve.flightProgress(atTime: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(DownloadFlyCurve.flightProgress(atTime: 0.5), 0.5, accuracy: 0.001)

        var previous = DownloadFlyCurve.flightProgress(atTime: 0)
        for step in 1...100 {
            let current = DownloadFlyCurve.flightProgress(atTime: CGFloat(step) / 100)
            XCTAssertGreaterThanOrEqual(current, previous)
            previous = current
        }
    }

    func testArcBowsTowardTheRoomierSideOfTheCanvas() {
        let nearTop = DownloadFlyArc(
            start: CGPoint(x: 0, y: 100),
            end: CGPoint(x: 100, y: 100),
            canvasHeight: 800
        )
        let nearBottom = DownloadFlyArc(
            start: CGPoint(x: 0, y: 700),
            end: CGPoint(x: 100, y: 700),
            canvasHeight: 800
        )

        XCTAssertEqual(nearTop.direction, 1)
        XCTAssertEqual(nearBottom.direction, -1)
    }

    func testArcHeightTakesTheSmallestOfItsThreeBounds() {
        let boundByDistance = DownloadFlyArc(
            start: CGPoint(x: 0, y: 400),
            end: CGPoint(x: 100, y: 400),
            canvasHeight: 2000
        )
        let boundByMaximum = DownloadFlyArc(
            start: CGPoint(x: 0, y: 1500),
            end: CGPoint(x: 3000, y: 1500),
            canvasHeight: 4000
        )
        let boundByAvailableSpace = DownloadFlyArc(
            start: CGPoint(x: 0, y: 100),
            end: CGPoint(x: 400, y: 100),
            canvasHeight: 200
        )

        XCTAssertEqual(boundByDistance.height, 80, accuracy: 0.001)
        XCTAssertEqual(boundByMaximum.height, DownloadFlyArc.maximumHeight, accuracy: 0.001)
        XCTAssertEqual(boundByAvailableSpace.height, 80, accuracy: 0.001)
    }

    func testFlightLandsExactlyOnItsEndpoints() {
        let start = CGPoint(x: 700, y: 360)
        let end = CGPoint(x: 60, y: 740)
        let arc = DownloadFlyArc(start: start, end: end, canvasHeight: 800)

        XCTAssertEqual(arc.frame(atTime: 0).position.x, start.x, accuracy: 0.001)
        XCTAssertEqual(arc.frame(atTime: 0).position.y, start.y, accuracy: 0.001)
        XCTAssertEqual(arc.frame(atTime: 1).position.x, end.x, accuracy: 0.001)
        XCTAssertEqual(arc.frame(atTime: 1).position.y, end.y, accuracy: 0.001)
    }

    func testFlightClearsBothEndpointsAtTheApex() {
        let start = CGPoint(x: 700, y: 360)
        let end = CGPoint(x: 60, y: 740)
        let arc = DownloadFlyArc(start: start, end: end, canvasHeight: 800)
        let apex = arc.frame(atTime: 0.5).position

        XCTAssertEqual(arc.direction, -1)
        XCTAssertLessThan(apex.y, start.y)
        XCTAssertLessThan(apex.y, end.y)
    }

    func testFlightSwellsAtTheApexAndShrinksIntoTheTarget() {
        XCTAssertEqual(DownloadFlyArc.scale(atProgress: 0), DownloadFlyArc.launchScale, accuracy: 0.001)
        XCTAssertEqual(DownloadFlyArc.scale(atProgress: 0.5), DownloadFlyArc.apexScale, accuracy: 0.001)
        XCTAssertEqual(DownloadFlyArc.scale(atProgress: 1), DownloadFlyArc.landingScale, accuracy: 0.001)

        let tolerance: CGFloat = 0.0001
        for step in 0...100 {
            let scale = DownloadFlyArc.scale(atProgress: CGFloat(step) / 100)
            XCTAssertGreaterThanOrEqual(scale, DownloadFlyArc.landingScale - tolerance)
            XCTAssertLessThanOrEqual(scale, DownloadFlyArc.apexScale + tolerance)
        }
    }

    func testFlightOpacityStaysWithinRangeAndEndsInvisible() {
        for step in 0...100 {
            let opacity = DownloadFlyArc.opacity(atProgress: CGFloat(step) / 100)
            XCTAssertGreaterThanOrEqual(opacity, 0)
            XCTAssertLessThanOrEqual(opacity, 1)
        }

        XCTAssertEqual(DownloadFlyArc.opacity(atProgress: 0.97), 1, accuracy: 0.001)
        XCTAssertEqual(DownloadFlyArc.opacity(atProgress: 1), 0, accuracy: 0.001)
    }

    func testBasketOffsetsMirrorWithSidebarPosition() {
        for phase in DownloadFlyBasketPhase.allCases {
            XCTAssertEqual(
                DownloadFlyBasketMotion.offset(
                    for: phase,
                    sidebarPosition: .left,
                    reducesMotion: false
                ),
                -DownloadFlyBasketMotion.offset(
                    for: phase,
                    sidebarPosition: .right,
                    reducesMotion: false
                ),
                accuracy: 0.001
            )
        }

        XCTAssertLessThan(
            DownloadFlyBasketMotion.offset(
                for: .parked,
                sidebarPosition: .left,
                reducesMotion: false
            ),
            0,
            "A left-hand basket parks past the left window edge"
        )
        XCTAssertGreaterThan(
            DownloadFlyBasketMotion.offset(
                for: .overshoot,
                sidebarPosition: .left,
                reducesMotion: false
            ),
            0,
            "The entry overshoots past the resting spot, into the window"
        )
    }

    func testReducedMotionBasketOnlyFades() {
        for phase in DownloadFlyBasketPhase.allCases {
            let standard = DownloadFlyBasketMotion.metrics(for: phase, reducesMotion: false)
            let reduced = DownloadFlyBasketMotion.metrics(for: phase, reducesMotion: true)

            XCTAssertEqual(reduced.outwardOffset, 0)
            XCTAssertEqual(reduced.scale, 1)
            XCTAssertEqual(reduced.opacity, standard.opacity)
        }
    }

    func testFlyingGlyphMovesAfterItIsMounted() async throws {
        let host = NSHostingView(
            rootView: DownloadFlyingGlyph(
                presentation: DownloadFlyPresentation(
                    id: UUID(),
                    arc: DownloadFlyArc(
                        start: CGPoint(x: 50, y: 320),
                        end: CGPoint(x: 350, y: 320),
                        canvasHeight: 400
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

        // The flight eases in slowly, so sample well past the halfway point.
        try await Task.sleep(for: .milliseconds(60))
        let initialCenter = try visiblePixelCenter(in: host)
        try await Task.sleep(for: .milliseconds(540))
        let animatedCenter = try visiblePixelCenter(in: host)

        XCTAssertGreaterThan(
            animatedCenter.x - initialCenter.x,
            100,
            "The download glyph remained at its initial position"
        )
    }

    func testFallbackRequestRendersInItsRegisteredWindow() async throws {
        let animationCenter = DownloadFlyAnimationCenter()
        let windowState = BrowserWindowState()
        windowState.isSidebarVisible = false
        let windowRegistry = WindowRegistry()
        let host = NSHostingView(
            rootView: DownloadFlyAnimationOverlay(
                animationCenter: animationCenter,
                downloadsPopoverPresenter: DownloadsPopoverPresenter(),
                windowState: windowState,
                windowRegistry: windowRegistry,
                sidebarPosition: .left
            )
        )
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        windowRegistry.bindAppKitWindow(window, to: windowState)
        window.orderFrontRegardless()
        defer {
            windowRegistry.unbindAppKitWindow(for: windowState.id)
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(try visiblePixelCount(in: host), 0)

        animationCenter.requestFallback(
            from: DownloadFlyAnimationOrigin(
                windowNumber: window.windowNumber,
                sourceRectInWindow: CGRect(
                    x: 300,
                    y: 180,
                    width: 44,
                    height: 44
                ),
                nativeOriginalRect: nil
            ),
            icon: testFileIcon
        )

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(
            try visiblePixelCount(in: host),
            0,
            "The registered fallback overlay did not render the request"
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

    private func visiblePixelCount(in host: NSView) throws -> Int {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var count = 0
        for row in 0 ..< bitmap.pixelsHigh {
            for column in 0 ..< bitmap.pixelsWide {
                if (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }
}
