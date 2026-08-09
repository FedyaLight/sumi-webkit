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
        }
        .frame(width: tileWidth, height: canvasHeight)
        .environment(SidebarFaviconImageStore()))
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

    /// Favorite tiles are the one sidebar surface whose width is a fraction of
    /// a point, so the live grid and the space-transition snapshot must agree on
    /// where the favicon rasterizes. They diverged once because the live tile
    /// always carries the press effect's geometry transform, which opts its
    /// contents out of pixel snapping: the icons jumped when a space switch
    /// swapped the grid for its snapshot.
    func testSnapshotTileFaviconMatchesLiveTileFaviconOnFractionalTileWidth() throws {
        let contentWidth: CGFloat = 234
        let columnCount = 4
        let tileWidth = (contentWidth
            - CGFloat(columnCount - 1) * PinnedTileMetrics.gridSpacing)
            / CGFloat(columnCount)
        XCTAssertNotEqual(
            tileWidth,
            tileWidth.rounded(),
            "This case only has teeth while the tile width is fractional"
        )

        let icon = Image(nsImage: solidIcon())
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)

        let liveRow = HStack(spacing: PinnedTileMetrics.gridSpacing) {
            ForEach(0..<columnCount, id: \.self) { _ in
                PinnedTileVisual(
                    tabIcon: icon,
                    glyphText: nil,
                    chromeTemplateSystemImageName: nil,
                    presentationState: .liveBackgrounded
                )
                .sidebarZenPressEffect(sourceID: "favorite-parity")
                .frame(width: tileWidth, height: PinnedTileMetrics.height)
            }
        }
        .environment(SidebarInteractionState())

        let snapshotItem = shortcutSnapshot(icon: icon)
        let snapshotRow = HStack(spacing: PinnedTileMetrics.gridSpacing) {
            ForEach(0..<columnCount, id: \.self) { _ in
                SpaceSnapshotPinnedTileView(
                    item: snapshotItem,
                    tileSize: CGSize(
                        width: tileWidth,
                        height: PinnedTileMetrics.height
                    ),
                    tokens: tokens
                )
            }
        }

        let liveColumns = try iconColumns(
            in: liveRow,
            width: contentWidth,
            settings: settings
        )
        let snapshotColumns = try iconColumns(
            in: snapshotRow,
            width: contentWidth,
            settings: settings
        )

        XCTAssertEqual(
            liveColumns.count,
            columnCount,
            "Expected one favicon run per favorite tile"
        )
        XCTAssertEqual(
            snapshotColumns,
            liveColumns,
            "Snapshot tiles must draw their favicons on the live tiles' pixels"
        )
    }

    /// The selected tile lifts off the sidebar as one silhouette. A `shadow`
    /// that is not flattened first is inherited by every drawn element, which
    /// made the favicon cast its own shadow onto the translucent selection
    /// plate.
    func testSelectedSnapshotTileFaviconCastsNoShadow() throws {
        let tileSize = CGSize(
            width: PinnedTileMetrics.minWidth,
            height: PinnedTileMetrics.height
        )
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let tile = SpaceSnapshotPinnedTileView(
            item: shortcutSnapshot(
                icon: Image(nsImage: solidIcon()),
                presentationState: .visuallySelected
            ),
            tileSize: tileSize,
            tokens: tokens
        )

        let representation = try renderedTile(tile, size: tileSize, settings: settings)
        let scale = CGFloat(representation.pixelsWide) / tileSize.width
        let centerX = tileSize.width / 2
        let centerY = tileSize.height / 2
        // Plate samples walking away from the favicon's right edge, all well
        // inside the selection ring.
        let plateBrightness: [CGFloat] = [11.5, 13, 14.5].map { offset in
            let color = representation.colorAt(
                x: Int((centerX + offset) * scale),
                y: Int(centerY * scale)
            )
            return color?.brightnessComponent ?? 0
        }

        let spread = (plateBrightness.max() ?? 0) - (plateBrightness.min() ?? 0)
        XCTAssertLessThan(
            spread,
            0.01,
            """
            Selection plate must be flat next to the favicon, \
            found \(plateBrightness)
            """
        )
    }

    private func renderedTile<Content: View>(
        _ tile: Content,
        size: CGSize,
        settings: SumiSettingsService
    ) throws -> NSBitmapImageRep {
        let root = tile
            .frame(width: size.width, height: size.height)
            .environment(\.sumiSettings, settings)
            .environment(SidebarFaviconImageStore())
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let representation = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: representation)
        return representation
    }

    /// Pixel columns covered by the tile favicons along the vertical center of
    /// a rendered favorite row, as `[first...last]` runs.
    private func iconColumns<Content: View>(
        in row: Content,
        width: CGFloat,
        settings: SumiSettingsService
    ) throws -> [ClosedRange<Int>] {
        let root = row
            .frame(width: width, height: PinnedTileMetrics.height, alignment: .leading)
            .environment(\.sumiSettings, settings)
            .environment(SidebarFaviconImageStore())
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: PinnedTileMetrics.height
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let representation = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: representation)

        let y = representation.pixelsHigh / 2
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0..<representation.pixelsWide {
            let color = representation.colorAt(x: x, y: y)
            let isIcon = (color?.alphaComponent ?? 0) > 0.5
                && (color?.redComponent ?? 0) > 0.5
                && (color?.greenComponent ?? 1) < 0.35
                && (color?.blueComponent ?? 1) < 0.35
            if isIcon, start == nil {
                start = x
            }
            if !isIcon, let started = start {
                runs.append(started...(x - 1))
                start = nil
            }
        }
        if let started = start {
            runs.append(started...(representation.pixelsWide - 1))
        }
        return runs
    }

    private func shortcutSnapshot(
        icon: Image,
        presentationState: ShortcutPresentationState = .liveBackgrounded
    ) -> SpaceShortcutSnapshot {
        SpaceShortcutSnapshot(
            id: UUID(),
            title: "Tile",
            icon: .image(icon),
            accentSource: SpaceShortcutSnapshotAccentSource(
                launchURL: URL(string: "https://example.com")!,
                partition: .regular(nil)
            ),
            favoriteBackdrop: nil,
            presentationState: presentationState,
            showsAudioButton: false,
            isMuted: false,
            showsSplitOutline: false,
            showsChangedURLSlash: false
        )
    }

    private func solidIcon() -> NSImage {
        let size = NSSize(
            width: PinnedTileMetrics.faviconHeight,
            height: PinnedTileMetrics.faviconHeight
        )
        return NSImage(size: size, flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
    }

    private func makeIsolatedSettings() -> SumiSettingsService {
        let suiteName = "PinnedTileVisualGeometryTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create isolated defaults")
        }
        return SumiSettingsService(userDefaults: defaults)
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
