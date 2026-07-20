import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class PinnedTileVisualGeometryTests: XCTestCase {
    func testSelectedBackdropDoesNotDrawOutsideTileHeight() throws {
        let tileWidth: CGFloat = 73
        let canvasHeight: CGFloat = 87
        let tile = PinnedTileVisual(
            tabIcon: Image(systemName: "globe"),
            glyphText: nil,
            chromeTemplateSystemImageName: nil,
            presentationState: .visuallySelected,
            selectionBackdrop: Image(nsImage: solidBackdrop())
        )
        .frame(width: tileWidth, height: PinnedTileMetrics.height)

        let host = NSHostingView(rootView: ZStack {
            Color.black
            tile
        }.frame(width: tileWidth, height: canvasHeight))
        host.frame = NSRect(x: 0, y: 0, width: tileWidth, height: canvasHeight)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        representation.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: representation)

        let scale = CGFloat(representation.pixelsHigh) / canvasHeight
        let expectedMinY = ((canvasHeight - PinnedTileMetrics.height) / 2) * scale
        let expectedMaxY = ((canvasHeight + PinnedTileMetrics.height) / 2) * scale
        let tolerance = max(1, Int(scale.rounded(.up)))

        var overflowingPixelCount = 0
        for y in 0..<representation.pixelsHigh where
            y < Int(expectedMinY) - tolerance
                || y >= Int(expectedMaxY) + tolerance {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y) else {
                    continue
                }
                if max(
                    color.redComponent,
                    color.greenComponent,
                    color.blueComponent
                ) >= 0.02 {
                    overflowingPixelCount += 1
                }
            }
        }
        XCTAssertEqual(
            overflowingPixelCount,
            0,
            "Backdrop must not draw outside the 47 pt tile"
        )
    }

    private func solidBackdrop() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
    }
}
