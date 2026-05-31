import SwiftData
import SwiftUI
import XCTest
@testable import Sumi

@MainActor
final class WorkspaceThemePersistenceTests: XCTestCase {
    func testCurrentThemeRoundTrips() throws {
        let theme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#445566",
                        isPrimary: true,
                        algorithm: .floating,
                        lightness: 0.35,
                        position: .monochrome
                    )
                ],
                opacity: 0.74,
                texture: 0.2
            )
        )

        let encoded = try XCTUnwrap(theme.encoded)
        let decoded = try XCTUnwrap(WorkspaceTheme.decode(encoded))

        XCTAssertEqual(decoded, theme)
        XCTAssertTrue(decoded.usesExplicitColorScheme)
    }

    func testLegacyThemePayloadIsRejected() {
        let legacyJSON = """
        {
          "gradient": {
            "angle": 12,
            "nodes": [],
            "grain": 0.2
          },
          "schemeMode": "dark"
        }
        """

        XCTAssertNil(WorkspaceTheme.decode(Data(legacyJSON.utf8)))
    }

    func testApplyingPresetDoesNotMutateGlobalWindowScheme() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.windowSchemeMode = .dark

        var workspaceTheme = WorkspaceTheme.default
        workspaceTheme = try! XCTUnwrap(
            SumiWorkspaceThemePresets.groups.first?.presets.dropFirst().first?.workspaceTheme
        )

        XCTAssertFalse(workspaceTheme.visuallyEquals(.default))
        XCTAssertEqual(settings.windowSchemeMode, .dark)
    }

    func testDefaultGradientMatchesFirstLightMonoPreset() throws {
        let firstLightMonoPreset = try XCTUnwrap(
            SumiWorkspaceThemePresets.groups.first?.presets.first?.workspaceTheme
        )

        XCTAssertEqual(firstLightMonoPreset.gradient.primaryColorHex, WorkspaceResolvedGradient.default.primaryColorHex)
        XCTAssertEqual(firstLightMonoPreset.gradient.opacity, WorkspaceResolvedGradient.default.opacity, accuracy: 0.0001)
        XCTAssertEqual(firstLightMonoPreset.gradient.texture, WorkspaceResolvedGradient.default.texture, accuracy: 0.0001)
        XCTAssertFalse(WorkspaceTheme.default.usesExplicitColorScheme)
        XCTAssertTrue(firstLightMonoPreset.usesExplicitColorScheme)
        XCTAssertEqual(WorkspaceResolvedGradient.default.primaryColorHex, "#F4EFDF")
        XCTAssertEqual(WorkspaceResolvedGradient.default.opacity, 0.62, accuracy: 0.0001)
        XCTAssertEqual(WorkspaceResolvedGradient.default.texture, 1.0 / 16.0, accuracy: 0.0001)
    }

    func testLegacyWorkspaceThemePayloadDefaultsExistingColoredThemesToExplicitScheme() throws {
        let legacyJSON = """
        {
          "gradientTheme": {
            "type": "gradient",
            "colors": [
              {
                "id": "\(UUID().uuidString)",
                "hex": "#F4EFDF",
                "isCustom": false,
                "isPrimary": true,
                "algorithm": "floating",
                "lightness": 0.9,
                "position": { "x": 0.6666666667, "y": 0.6666666667 },
                "type": "explicit-lightness"
              }
            ],
            "opacity": 0.62,
            "texture": 0.0625
          }
        }
        """

        let decoded = try XCTUnwrap(WorkspaceTheme.decode(Data(legacyJSON.utf8)))

        XCTAssertTrue(decoded.usesExplicitColorScheme)
    }

    func testTextureQuantizesToZenSixteenthStepsAndWrapsFullTurn() {
        var theme = WorkspaceGradientTheme.default

        theme.updateTexture(0.61)
        XCTAssertEqual(theme.texture, 0.625, accuracy: 0.0001)

        theme.updateTexture(1.0)
        XCTAssertEqual(theme.texture, 0.0, accuracy: 0.0001)
    }

    func testCustomChromeIntensitySnapsAtLightweightEdges() {
        let hidden = WorkspaceGradientTheme(colors: makeThemeColors(), opacity: 0.019, texture: 0.18)
        XCTAssertEqual(hidden.customChromeThemeIntensity, 0, accuracy: 0.0001)
        XCTAssertFalse(hidden.usesCustomChromeTheme)
        XCTAssertFalse(hidden.rendersOpaqueCustomChromeTheme)

        let visible = WorkspaceGradientTheme(colors: makeThemeColors(), opacity: 0.02, texture: 0.18)
        XCTAssertEqual(visible.customChromeThemeIntensity, 0.02, accuracy: 0.0001)
        XCTAssertTrue(visible.usesCustomChromeTheme)
        XCTAssertFalse(visible.rendersOpaqueCustomChromeTheme)

        let opaque = WorkspaceGradientTheme(colors: makeThemeColors(), opacity: 0.98, texture: 0.18)
        XCTAssertEqual(opaque.customChromeThemeIntensity, 1, accuracy: 0.0001)
        XCTAssertTrue(opaque.usesCustomChromeTheme)
        XCTAssertTrue(opaque.rendersOpaqueCustomChromeTheme)
    }

    func testGradientThemeAllowsZeroPersistedDotsWithoutDefaultFallback() {
        let theme = WorkspaceGradientTheme(colors: [], opacity: 0.64, texture: 0.18)

        XCTAssertTrue(theme.normalizedColors.isEmpty)
        XCTAssertTrue(theme.renderGradient.stops.isEmpty)
    }

    func testStartupWorkspaceThemeResolverUsesPersistedActiveSpaceTheme() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let spaceId = UUID()
        let expectedTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .topLeft
                    ),
                    WorkspaceThemeColor(
                        hex: "#34C759",
                        position: .bottom
                    )
                ],
                opacity: 0.82,
                texture: 0.25
            )
        )
        let space = SpaceEntity(
            id: spaceId,
            name: "Startup",
            icon: "sparkles",
            index: 0,
            workspaceThemeData: expectedTheme.encoded
        )
        context.insert(space)
        try context.save()

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let snapshot = WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: spaceId,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false),
            splitSession: nil
        )
        harness.defaults.set(try JSONEncoder().encode(snapshot), forKey: sessionKey)

        let resolvedTheme = try XCTUnwrap(
            StartupWorkspaceThemeResolver.resolve(
                userDefaults: harness.defaults,
                lastWindowSessionKey: sessionKey,
                modelContext: context
            )
        )

        XCTAssertEqual(resolvedTheme, expectedTheme)
        XCTAssertFalse(resolvedTheme.visuallyEquals(.default))
    }

    private func makeThemeColors() -> [WorkspaceThemeColor] {
        [
            WorkspaceThemeColor(
                hex: "#F4EFDF",
                isPrimary: true,
                algorithm: .floating,
                lightness: 0.9,
                position: .monochrome
            )
        ]
    }
}
