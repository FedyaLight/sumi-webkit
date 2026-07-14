import AppKit
import SumiDomain
import SwiftUI
import XCTest

@testable import Sumi

final class WorkspaceThemeRenderingTests: XCTestCase {
    func testRenderGradientPreservesStopLocationsAndDerivesAngle() {
        let theme = WorkspaceGradientTheme(
            colors: [
                color(id: 1, hex: "#FF0000", position: .topLeft),
                color(id: 2, hex: "#00FF00", position: .monochrome),
                color(id: 3, hex: "#0000FF", position: .bottom),
            ],
            opacity: 0.74,
            texture: 0.2
        )

        let gradient = theme.renderGradient

        XCTAssertEqual(gradient.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(gradient.stops.map(\.hex), ["#FF0000", "#00FF00", "#0000FF"])
        XCTAssertEqual(
            gradient.angle,
            Angle(
                radians: atan2(
                    WorkspaceThemePosition.bottom.y - WorkspaceThemePosition.topLeft.y,
                    WorkspaceThemePosition.bottom.x - WorkspaceThemePosition.topLeft.x
                )
            ).degrees,
            accuracy: 0.0001
        )
        XCTAssertEqual(gradient.opacity, 0.74)
        XCTAssertEqual(gradient.texture, 0.1875)
    }

    func testAppKitDefaultLightnessAndColorConversionMatchHistoricalSRGBBehavior() {
        let expected = 467.0 / 510.0

        XCTAssertEqual(
            WorkspaceThemeColor.defaultLightness(for: "#F4EFDF"),
            expected,
            accuracy: 1e-8
        )

        let color = WorkspaceThemeColor(
            hex: "#f4efdf",
            position: .monochrome
        )
        XCTAssertEqual(color.hex, "#F4EFDF")
        XCTAssertEqual(color.lightness, expected, accuracy: 1e-8)
        XCTAssertEqual(
            NSColor(color.color).themePerceivedLightness,
            expected,
            accuracy: 1e-8
        )
    }

    func testDomainIncognitoLightnessMatchesHistoricalAppKitSRGBBehavior() {
        let colors = WorkspaceGradientTheme.incognito.colors

        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(colors.map(\.lightness), [58.0 / 510.0, 90.0 / 510.0])
        for color in colors {
            XCTAssertEqual(
                color.lightness,
                WorkspaceThemeColor.defaultLightness(for: color.hex),
                accuracy: 1e-8
            )
        }
    }

    func testWorkspaceThemeInterpolationSwitchesAtHalf() {
        let source = WorkspaceTheme.default
        let target = WorkspaceTheme.incognito

        XCTAssertEqual(source.interpolated(to: target, progress: -1), source)
        XCTAssertEqual(source.interpolated(to: target, progress: 0.499), source)
        XCTAssertEqual(source.interpolated(to: target, progress: 0.5), target)
        XCTAssertEqual(source.interpolated(to: target, progress: 2), target)
    }

    func testResolvedGradientInterpolationUsesShortestAngleAndSRGBHexBlend() {
        let source = WorkspaceResolvedGradient(
            angle: 350,
            stops: [
                WorkspaceGradientStop(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                    hex: "#FF0000",
                    location: 0,
                    position: .topLeft
                ),
            ],
            texture: 0,
            opacity: 0.2
        )
        let target = WorkspaceResolvedGradient(
            angle: 10,
            stops: [
                WorkspaceGradientStop(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                    hex: "#0000FF",
                    location: 1,
                    position: .bottom
                ),
            ],
            texture: 1,
            opacity: 0.8
        )

        let midpoint = source.interpolated(to: target, progress: 0.5)

        XCTAssertEqual(midpoint.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(midpoint.stops.first?.hex, "#800080")
        XCTAssertEqual(midpoint.stops.first?.location ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midpoint.texture, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midpoint.opacity, 0.5, accuracy: 0.0001)
    }

    func testResolvedDefaultRetainsLegacyPositionDistinctFromDurablePresetDefault() throws {
        let resolvedPosition = try XCTUnwrap(WorkspaceResolvedGradient.default.stops.first?.position)
        let durablePosition = try XCTUnwrap(
            WorkspaceGradientTheme.default.normalizedColors.first?.position
        )

        XCTAssertEqual(resolvedPosition, .monochrome)
        XCTAssertNotEqual(resolvedPosition, durablePosition)
        XCTAssertEqual(durablePosition.x, 240.0 / 360.0)
        XCTAssertEqual(durablePosition.y, 240.0 / 360.0)
    }

    private func color(
        id: Int,
        hex: String,
        position: WorkspaceThemePosition
    ) -> WorkspaceThemeColor {
        WorkspaceThemeColor(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            hex: hex,
            lightness: 0.5,
            position: position
        )
    }
}
