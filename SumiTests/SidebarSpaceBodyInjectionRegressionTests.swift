import Combine
import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpaceBodyInjectionRegressionTests: XCTestCase {
    func testSidebarStructuralInvalidationTracksProfileRuntimeState() {
        let browserManager = BrowserManager()
        let context = WindowViewBrowserContext.live(
            browserManager: browserManager,
            updaterService: SumiUpdaterService(backendFactory: { _ in nil }),
            defaultBrowserService: SumiDefaultBrowserService()
        )
        var invalidationCount = 0
        let cancellable = context.sidebarStructuralInvalidation.sink {
            invalidationCount += 1
        }
        let initialInvalidationCount = invalidationCount

        browserManager.isTransitioningProfile = true
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 1)

        browserManager.isTransitioningProfile = false
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 2)

        browserManager.currentProfile = Profile(name: "Sidebar Runtime")
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 3)

        browserManager.tabStructuralRevision &+= 1
        XCTAssertEqual(invalidationCount, initialInvalidationCount + 4)

        cancellable.cancel()
    }

    func testSidebarColumnHostedRootCarriesInjectedDragState() throws {
        let nowPlayingController = SumiNativeNowPlayingController()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })
        let browserManager = BrowserManager(nowPlayingController: nowPlayingController)
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let dragState = SidebarDragState()
        let settingsSuiteName = "SumiTests.sidebarDragState.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        defer {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }

        let environmentContext = SidebarHostEnvironmentContext(
            browserContext: SidebarBrowserContext.live(browserManager: browserManager),
            hostActions: SidebarHostActions(
                updateSidebarWidth: { _, _, _ in /* No-op. */ },
                persistWindowSession: { _ in /* No-op. */ },
                dismissThemePickerCommittingIfNeeded: { /* No-op. */ }
            ),
            structuralInvalidation: Empty().eraseToAnyPublisher(),
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: SumiSettingsService(userDefaults: settingsDefaults),
            nowPlayingController: nowPlayingController,
            updaterService: updaterService,
            resolvedThemeContext: .default,
            chromeBackgroundResolvedThemeContext: .default,
            windowChromeSize: CGSize(width: 320, height: 640),
            sidebarDragState: dragState
        )
        let root = SidebarColumnHostedRoot.view(
            environmentContext: environmentContext,
            presentationContext: .docked(sidebarWidth: 280)
        )

        XCTAssertIdentical(root.environmentContext.sidebarDragState, dragState)
        XCTAssertIdentical(root.environmentContext.sidebarDragState.locationTracker, dragState.locationTracker)
        XCTAssertIdentical(root.environmentContext.nowPlayingController, nowPlayingController)
        XCTAssertIdentical(root.environmentContext.updaterService, updaterService)
        XCTAssertIdentical(root.environmentContext.browserContext.extensionSurfaceStore, browserManager.extensionSurfaceStore)
        XCTAssertEqual(root.presentationContext, .docked(sidebarWidth: 280))
    }
}
