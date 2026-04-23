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

        XCTAssertTrue(WorkspaceTheme.default.visuallyEquals(firstLightMonoPreset))
        XCTAssertEqual(SpaceGradient.default.primaryColorHex, "#F4EFDF")
        XCTAssertEqual(SpaceGradient.default.opacity, 0.62, accuracy: 0.0001)
        XCTAssertEqual(SpaceGradient.default.grain, 1.0 / 16.0, accuracy: 0.0001)
    }

    func testTextureQuantizesToZenSixteenthStepsAndWrapsFullTurn() {
        var theme = WorkspaceGradientTheme.default

        theme.updateTexture(0.61)
        XCTAssertEqual(theme.texture, 0.625, accuracy: 0.0001)

        theme.updateTexture(1.0)
        XCTAssertEqual(theme.texture, 0.0, accuracy: 0.0001)
    }

    func testGradientThemeAllowsZeroPersistedDotsWithoutDefaultFallback() {
        let theme = WorkspaceGradientTheme(colors: [], opacity: 0.64, texture: 0.18)

        XCTAssertTrue(theme.normalizedColors.isEmpty)
        XCTAssertTrue(theme.renderGradient.nodes.isEmpty)
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
            gradient: SpaceGradient(
                angle: 132,
                nodes: [
                    GradientNode(colorHex: "#FF3B30", location: 0.0),
                    GradientNode(colorHex: "#34C759", location: 1.0)
                ],
                grain: 0.25,
                opacity: 0.82
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
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            urlBarDraft: URLBarDraftState(text: "", navigateCurrentTab: false),
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
}
