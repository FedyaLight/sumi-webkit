import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpaceBodySourceGuardTests: XCTestCase {
    func testSidebarColumnHostedRootCarriesInjectedDragState() throws {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.sidebarDragState.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }

        let root = SidebarColumnHostedRoot.view(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState,
            presentationContext: .docked(sidebarWidth: 280)
        )

        XCTAssertTrue(root.environmentContext.sidebarDragState === dragState)
        XCTAssertTrue(root.environmentContext.sidebarDragState.locationTracker === dragState.locationTracker)
        XCTAssertFalse(root.environmentContext.sidebarDragState === SidebarDragState.shared)
        XCTAssertEqual(root.presentationContext, .docked(sidebarWidth: 280))
    }
}
