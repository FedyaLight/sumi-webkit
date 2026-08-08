import AppKit
import CoreGraphics
@testable import Sumi
import SumiDomain
import SwiftUI
import XCTest

/// The spaces-strip hover label: which shortcut covers a strip position, what
/// the plate renders, where it sits, how it is tinted, and when it opens.
final class SpaceHoverLabelTests: XCTestCase {
    // MARK: - Shortcut coverage

    func testSpaceSwitchShortcutsRoundTripPositionAndAction() {
        for (index, action) in SpaceSwitchShortcuts.actions.enumerated() {
            XCTAssertEqual(SpaceSwitchShortcuts.action(forSpaceAt: index), action)
            XCTAssertEqual(SpaceSwitchShortcuts.spaceIndex(for: action), index)
        }
    }

    func testSpacesPastTheCoveredRangeHaveNoShortcut() {
        XCTAssertNil(SpaceSwitchShortcuts.action(forSpaceAt: SpaceSwitchShortcuts.actions.count))
        XCTAssertNil(SpaceSwitchShortcuts.action(forSpaceAt: -1))
        XCTAssertNil(SpaceSwitchShortcuts.spaceIndex(for: .goToTab1))
        XCTAssertNil(SpaceSwitchShortcuts.spaceIndex(for: .nextSpace))
    }

    func testDefaultSpaceShortcutsAreControlDigitsWithoutDuplicateAppBindings() {
        let defaults = DefaultKeyboardShortcuts.shortcutsByAction
        let expectedKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

        for (index, action) in SpaceSwitchShortcuts.actions.enumerated() {
            let combination = try? XCTUnwrap(defaults[action]?.keyCombination)
            XCTAssertEqual(combination?.key, expectedKeys[index])
            XCTAssertEqual(combination?.modifiers, [.control])
        }

        let lookupKeys = DefaultKeyboardShortcuts.shortcuts.compactMap(\.lookupKey)
        XCTAssertEqual(lookupKeys.count, Set(lookupKeys).count)
    }

    // MARK: - Label contents

    @MainActor
    func testLabelCarriesOneGlyphPerKeyOfTheBoundShortcut() {
        let shortcuts = makeShortcutManager()
        let space = Space(name: "Personal")

        let label = SpaceHoverLabelBuilder.label(for: space, at: 0, shortcuts: shortcuts)

        XCTAssertEqual(label.spaceID, space.id)
        XCTAssertEqual(label.title, "Personal")
        XCTAssertEqual(label.shortcutGlyphs, ["⌃", "1"])
    }

    @MainActor
    func testLabelDropsGlyphsWhenTheUserClearedTheBinding() {
        let shortcuts = makeShortcutManager()
        shortcuts.clearShortcut(action: .goToSpace2)

        let label = SpaceHoverLabelBuilder.label(
            for: Space(name: "Work"),
            at: 1,
            shortcuts: shortcuts
        )

        XCTAssertEqual(label.title, "Work")
        XCTAssertTrue(label.shortcutGlyphs.isEmpty)
    }

    @MainActor
    func testLabelFollowsARebindingIncludingItsModifierOrder() {
        let shortcuts = makeShortcutManager()
        XCTAssertEqual(
            shortcuts.setShortcut(
                action: .goToSpace1,
                keyCombination: KeyCombination(key: "j", modifiers: [.command, .shift, .control])
            ),
            .valid
        )

        let label = SpaceHoverLabelBuilder.label(
            for: Space(name: "Personal"),
            at: 0,
            shortcuts: shortcuts
        )

        XCTAssertEqual(label.shortcutGlyphs, ["⌃", "⇧", "⌘", "J"])
    }

    @MainActor
    func testLabelHasNoGlyphsForSpacesPastTheCoveredRange() {
        let label = SpaceHoverLabelBuilder.label(
            for: Space(name: "Eleventh"),
            at: SpaceSwitchShortcuts.actions.count,
            shortcuts: makeShortcutManager()
        )

        XCTAssertTrue(label.shortcutGlyphs.isEmpty)
    }

    // MARK: - Placement

    func testLabelCenterFollowsItsResolvedIconAnchor() {
        XCTAssertEqual(
            SpaceHoverLabelPlacement.centerX(
                anchorX: 116,
                containerWidth: 300,
                labelWidth: 80
            ),
            116,
            accuracy: 0.001
        )
    }

    func testLabelCenterGivesWayAtBothContainerEdges() {
        XCTAssertEqual(
            SpaceHoverLabelPlacement.centerX(
                anchorX: 16,
                containerWidth: 300,
                labelWidth: 120
            ),
            60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SpaceHoverLabelPlacement.centerX(
                anchorX: 284,
                containerWidth: 300,
                labelWidth: 120
            ),
            240,
            accuracy: 0.001
        )
    }

    func testOversizedLabelFallbackPinsToTheLeadingEdge() {
        let centerX = SpaceHoverLabelPlacement.centerX(
            anchorX: 100,
            containerWidth: 120,
            labelWidth: 200
        )

        XCTAssertEqual(centerX - 100, 0, accuracy: 0.001)
    }

    func testLabelFrameAlignsToRetinaPixelGrid() {
        let scale: CGFloat = 2
        let size = CGSize(width: 83.25, height: 34.25)
        let frame = SpaceHoverLabelPlacement.frame(
            anchorX: 116.25,
            targetMinY: 40.25,
            containerBounds: CGRect(x: 0, y: 0, width: 300, height: 80),
            labelSize: size,
            displayScale: scale
        )

        for edge in [frame.minX, frame.minY, frame.maxX, frame.maxY] {
            XCTAssertEqual(edge * scale, (edge * scale).rounded(), accuracy: 0.001)
        }
    }

    // MARK: - Palette

    @MainActor
    func testPlateAndChipsTakeTheirDocumentedShareOfAccent() {
        let palette = SpaceHoverLabelPalette.make(base: .white, accent: .black)

        // White mixed toward black by the blend amount.
        XCTAssertEqual(
            Double(palette.surface.sRGBComponents.red),
            1 - Double(SpaceHoverLabelPalette.surfaceAccentBlend),
            accuracy: 0.01
        )
        XCTAssertEqual(
            Double(palette.chipFill.sRGBComponents.red),
            1 - Double(SpaceHoverLabelPalette.chipAccentBlend),
            accuracy: 0.01
        )
    }

    @MainActor
    func testChipsCarryMoreAccentThanThePlateTheySitOn() {
        let accent = Color(red: 0.85, green: 0.35, blue: 0.42)
        let palette = SpaceHoverLabelPalette.make(base: .white, accent: accent)

        XCTAssertGreaterThan(
            palette.surface.relativeLuminance,
            palette.chipFill.relativeLuminance
        )
    }

    @MainActor
    func testChipFaceDoublesSaturationWithoutChangingItsBrightness() {
        let base = Color.white
        let accent = Color(red: 0.85, green: 0.35, blue: 0.42)
        let unboosted = base.mixed(
            with: accent,
            amount: SpaceHoverLabelPalette.chipAccentBlend
        )
        let palette = SpaceHoverLabelPalette.make(base: base, accent: accent)
        let before = hsba(unboosted)
        let after = hsba(palette.chipFill)

        XCTAssertEqual(
            after.saturation,
            min(before.saturation * SpaceHoverLabelPalette.chipSaturationMultiplier, 1),
            accuracy: 0.01
        )
        XCTAssertEqual(after.brightness, before.brightness, accuracy: 0.01)
    }

    @MainActor
    func testPlateOutlineIsVisibleButSubtleInLightAndDarkChrome() {
        let accent = Color(red: 0.85, green: 0.35, blue: 0.42)

        for base in [Color.white, Color(hex: "12151A")] {
            let palette = SpaceHoverLabelPalette.make(base: base, accent: accent)
            let contrast = palette.surfaceBorder.contrastRatio(with: palette.surface)

            XCTAssertGreaterThan(contrast, 1.05)
            XCTAssertLessThan(contrast, 1.5)
        }
    }

    @MainActor
    func testTextStaysReadableOnBothFillsInLightAndDarkBases() {
        let accent = Color(red: 0.85, green: 0.35, blue: 0.42)

        for base in [Color.white, Color(hex: "12151A")] {
            let palette = SpaceHoverLabelPalette.make(base: base, accent: accent)
            XCTAssertGreaterThanOrEqual(
                palette.titleText.contrastRatio(with: palette.surface),
                Double(SpaceHoverLabelPalette.textContrastRatio) - 0.05
            )
            XCTAssertGreaterThanOrEqual(
                palette.chipText.contrastRatio(with: palette.chipFill),
                Double(SpaceHoverLabelPalette.textContrastRatio) - 0.05
            )
        }
    }

    @MainActor
    func testDarkNativeSurfaceContextProducesDarkHoverPlate() {
        let defaults = TestDefaultsHarness()
        defer { defaults.reset() }
        let settings = SumiSettingsService(userDefaults: defaults.defaults)
        var context = ResolvedThemeContext.default
        context.globalColorScheme = .dark
        context.chromeColorScheme = .dark
        context.sourceChromeColorScheme = .light
        context.targetChromeColorScheme = .dark
        context.transitionProgress = 1

        let nativeContext = context.nativeSurfaceThemeContext
        let palette = SpaceHoverLabelPalette.make(
            tokens: nativeContext.tokens(settings: settings)
        )

        XCTAssertEqual(nativeContext.chromeColorScheme, .dark)
        XCTAssertLessThan(palette.surface.relativeLuminance, 0.2)
        XCTAssertGreaterThanOrEqual(
            palette.titleText.contrastRatio(with: palette.surface),
            Double(SpaceHoverLabelPalette.textContrastRatio) - 0.05
        )
    }

    @MainActor
    func testChipBorderSitsBetweenItsFillAndItsGlyph() {
        let palette = SpaceHoverLabelPalette.make(
            base: .white,
            accent: Color(red: 0.85, green: 0.35, blue: 0.42)
        )

        // Darker than the face it edges, lighter than the glyph on it.
        XCTAssertLessThan(palette.chipBorder.relativeLuminance, palette.chipFill.relativeLuminance)
        XCTAssertGreaterThan(palette.chipBorder.relativeLuminance, palette.chipText.relativeLuminance)
    }

    // MARK: - Hover session

    @MainActor
    func testFirstHoverWaitsForThePointerToRest() async {
        let session = SpaceHoverLabelSession(openDelay: .zero)
        let spaceID = UUID()

        session.hoverBegan(spaceID)
        XCTAssertEqual(session.hoveredSpaceID, spaceID)
        XCTAssertNil(session.visibleSpaceID, "the label must not open synchronously")

        await session.openTask?.value
        XCTAssertEqual(session.visibleSpaceID, spaceID)
    }

    @MainActor
    func testLeavingBeforeTheRestElapsesNeverOpensTheLabel() async {
        let session = SpaceHoverLabelSession(openDelay: .zero)
        let spaceID = UUID()

        session.hoverBegan(spaceID)
        let pendingOpen = session.openTask
        session.hoverEnded(spaceID)

        await pendingOpen?.value
        XCTAssertNil(session.visibleSpaceID)
        XCTAssertNil(session.hoveredSpaceID)
    }

    @MainActor
    func testAnOpenLabelHandsOverToTheNextIconWithoutWaitingAgain() async {
        let session = SpaceHoverLabelSession(openDelay: .zero)
        let first = UUID()
        let second = UUID()

        session.hoverBegan(first)
        await session.openTask?.value
        XCTAssertEqual(session.visibleSpaceID, first)

        // Synchronously, without awaiting anything: the rest is not served twice.
        session.hoverBegan(second)
        XCTAssertEqual(session.visibleSpaceID, second)
    }

    @MainActor
    func testLeavingOneIconInsideTheStripKeepsTheInstantHandover() async {
        let session = SpaceHoverLabelSession(
            openDelay: .zero,
            handoffDelay: .milliseconds(100)
        )
        let first = UUID()
        let second = UUID()

        session.hoverBegan(first)
        await session.openTask?.value
        session.hoverEnded(first)
        XCTAssertEqual(
            session.visibleSpaceID,
            first,
            "the plate must survive the item-exit half of an adjacent hand-off"
        )

        session.hoverBegan(second)
        XCTAssertEqual(session.visibleSpaceID, second)
    }

    @MainActor
    func testPlateClosesWhenNoNeighbourTakesTheHandoff() async {
        let session = SpaceHoverLabelSession(
            openDelay: .zero,
            handoffDelay: .zero
        )
        let spaceID = UUID()

        session.hoverBegan(spaceID)
        await session.openTask?.value
        session.hoverEnded(spaceID)
        await session.closeTask?.value

        XCTAssertNil(session.visibleSpaceID)
    }

    @MainActor
    func testStaleHoverEndFromAnotherIconIsIgnored() async {
        let session = SpaceHoverLabelSession(openDelay: .zero)
        let hovered = UUID()

        session.hoverBegan(hovered)
        await session.openTask?.value
        session.hoverEnded(UUID())

        XCTAssertEqual(session.hoveredSpaceID, hovered)
        XCTAssertEqual(session.visibleSpaceID, hovered)
    }

    @MainActor
    func testSuppressTakesTheLabelDownAndRearmsTheRest() async {
        let session = SpaceHoverLabelSession(openDelay: .zero)
        let first = UUID()
        let second = UUID()

        session.hoverBegan(first)
        await session.openTask?.value
        session.suppress()

        XCTAssertNil(session.hoveredSpaceID)
        XCTAssertNil(session.visibleSpaceID)

        session.hoverBegan(second)
        XCTAssertNil(session.visibleSpaceID, "the rest must be served again")
        await session.openTask?.value
        XCTAssertEqual(session.visibleSpaceID, second)
    }

    // MARK: - Helpers

    @MainActor
    private func makeShortcutManager() -> KeyboardShortcutManager {
        let suiteName = "SpaceHoverLabelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return KeyboardShortcutManager(userDefaults: defaults)
    }

    @MainActor
    private func hsba(
        _ color: Color
    ) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        return (hue, saturation, brightness, alpha)
    }
}
