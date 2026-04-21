import CoreGraphics
import XCTest
@testable import Sumi

final class SumiThemePickerHarmonyTests: XCTestCase {
    func testActionStateMatchesZenMatrix() {
        XCTAssertEqual(
            SumiThemePickerActionState.resolve(dotCount: 0),
            SumiThemePickerActionState(
                canAdd: false,
                canRemove: false,
                canCycleHarmony: false,
                showsClickToAdd: true
            )
        )
        XCTAssertEqual(
            SumiThemePickerActionState.resolve(dotCount: 1),
            SumiThemePickerActionState(
                canAdd: true,
                canRemove: true,
                canCycleHarmony: false,
                showsClickToAdd: false
            )
        )
        XCTAssertEqual(
            SumiThemePickerActionState.resolve(dotCount: 2),
            SumiThemePickerActionState(
                canAdd: true,
                canRemove: true,
                canCycleHarmony: true,
                showsClickToAdd: false
            )
        )
        XCTAssertEqual(
            SumiThemePickerActionState.resolve(dotCount: 3),
            SumiThemePickerActionState(
                canAdd: false,
                canRemove: true,
                canCycleHarmony: true,
                showsClickToAdd: false
            )
        )
    }

    func testSingleDotThemesInferFloatingHarmony() {
        let colors = [
            WorkspaceThemeColor(
                hex: "#F4EFDF",
                isPrimary: true,
                algorithm: .floating,
                lightness: 0.9,
                position: WorkspaceThemePosition(x: 0.66, y: 0.5)
            )
        ]

        XCTAssertEqual(SumiThemePickerHarmony.infer(from: colors), .floating)
    }

    func testTwoDotAnalogousThemesInferSingleAnalogousHarmony() {
        let geometry = SumiThemePickerFieldGeometry(size: CGSize(width: 358, height: 358))
        let primary = WorkspaceThemeColor(
            hex: "#F0B8CD",
            isPrimary: true,
            algorithm: .analogous,
            lightness: 0.8,
            position: WorkspaceThemePosition(x: 0.65, y: 0.44)
        )
        let colors = SumiThemePickerHarmony.rebuildColors(
            from: [primary],
            targetCount: 2,
            harmony: .singleAnalogous,
            geometry: geometry
        )

        XCTAssertEqual(SumiThemePickerHarmony.infer(from: colors), .singleAnalogous)
    }

    func testThreeDotThemesInferTriadicHarmony() {
        let geometry = SumiThemePickerFieldGeometry(size: CGSize(width: 358, height: 358))
        let primary = WorkspaceThemeColor(
            hex: "#DA7682",
            isPrimary: true,
            algorithm: .triadic,
            lightness: 0.7,
            position: WorkspaceThemePosition(x: 0.65, y: 0.4)
        )
        let colors = SumiThemePickerHarmony.rebuildColors(
            from: [primary],
            targetCount: 3,
            harmony: .triadic,
            geometry: geometry
        )

        XCTAssertEqual(SumiThemePickerHarmony.infer(from: colors), .triadic)
    }

    func testHarmonyCyclingFollowsZenOrder() {
        XCTAssertEqual(
            SumiThemePickerHarmony.next(after: .complementary, dotCount: 2),
            .singleAnalogous
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.next(after: .singleAnalogous, dotCount: 2),
            .complementary
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.next(after: .splitComplementary, dotCount: 3),
            .analogous
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.next(after: .analogous, dotCount: 3),
            .triadic
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.next(after: .triadic, dotCount: 3),
            .splitComplementary
        )
    }

    func testHarmonyAddAndRemoveFollowZenOrder() {
        XCTAssertEqual(
            SumiThemePickerHarmony.addedHarmony(from: .floating, currentDotCount: 1),
            .complementary
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.addedHarmony(from: .singleAnalogous, currentDotCount: 2),
            .splitComplementary
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.removedHarmony(resultingDotCount: 2),
            .complementary
        )
        XCTAssertEqual(
            SumiThemePickerHarmony.removedHarmony(resultingDotCount: 1),
            .floating
        )
    }

    func testRebuildingColorsRepositionsCompanionDotsAroundPrimary() {
        let geometry = SumiThemePickerFieldGeometry(size: CGSize(width: 358, height: 358))
        let primary = WorkspaceThemeColor(
            hex: "#F3BEDE",
            isPrimary: true,
            algorithm: .splitComplementary,
            lightness: 0.85,
            position: WorkspaceThemePosition(x: 0.74, y: 0.34)
        )
        let rebuilt = SumiThemePickerHarmony.rebuildColors(
            from: [primary],
            targetCount: 3,
            harmony: .splitComplementary,
            geometry: geometry
        )

        XCTAssertEqual(rebuilt.count, 3)
        XCTAssertEqual(rebuilt.first?.id, primary.id)

        let offsets = rebuilt.dropFirst().map {
            angularOffset(from: primary.position, to: $0.position)
        }.sorted()
        XCTAssertEqual(offsets[0], 150, accuracy: 0.5)
        XCTAssertEqual(offsets[1], 210, accuracy: 0.5)
    }

    func testPixelGeometryRoundTripsBackToNormalizedPositions() {
        let geometry = SumiThemePickerFieldGeometry(size: CGSize(width: 358, height: 358))
        let position = WorkspaceThemePosition(x: 0.68, y: 0.32)
        let pixelPoint = geometry.point(for: position)
        let restored = geometry.normalizedPosition(for: pixelPoint)

        XCTAssertEqual(restored.x, position.x, accuracy: 0.0001)
        XCTAssertEqual(restored.y, position.y, accuracy: 0.0001)
    }

    func testPrimaryColorCreationUsesPixelSpaceAndPersistsFloatingMode() {
        let geometry = SumiThemePickerFieldGeometry(size: CGSize(width: 358, height: 358))
        let color = SumiThemePickerHarmony.makePrimaryColor(
            at: CGPoint(x: 280, y: 110),
            geometry: geometry,
            lightness: 0.8,
            type: .explicitLightness
        )

        XCTAssertEqual(color.algorithm, .floating)
        XCTAssertEqual(color.position.x, 280.0 / 358.0, accuracy: 0.0001)
        XCTAssertEqual(color.position.y, 110.0 / 358.0, accuracy: 0.0001)
        XCTAssertTrue(color.hex.hasPrefix("#"))
    }

    private func angularOffset(
        from primary: WorkspaceThemePosition,
        to companion: WorkspaceThemePosition
    ) -> Double {
        let primaryAngle = atan2(primary.y - 0.5, primary.x - 0.5) * 180 / .pi
        let companionAngle = atan2(companion.y - 0.5, companion.x - 0.5) * 180 / .pi
        let normalizedPrimary = primaryAngle < 0 ? primaryAngle + 360 : primaryAngle
        let normalizedCompanion = companionAngle < 0 ? companionAngle + 360 : companionAngle
        let rawOffset = normalizedCompanion - normalizedPrimary
        return rawOffset >= 0 ? rawOffset : rawOffset + 360
    }
}
