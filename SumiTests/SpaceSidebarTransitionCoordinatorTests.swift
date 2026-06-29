@testable import Sumi
import XCTest

@MainActor
final class SpaceSidebarTransitionCoordinatorTests: XCTestCase {
    func testScheduledClickCompletionResolvesDestinationFromCurrentSpaces() async throws {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let staleDestination = Space(name: "Deleted", profileId: destinationProfileId)
        let replacement = Space(name: "Replacement", profileId: destinationProfileId)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [source, staleDestination]
        browserManager.tabManager.currentSpace = source
        windowState.tabManager = browserManager.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, staleDestination],
            currentSpaces: { browserManager.tabManager.spaces },
            windowState: windowState,
            browserContext: SidebarBrowserContext.live(browserManager: browserManager),
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.switchSpace(to: staleDestination, context: context)
        browserManager.tabManager.spaces = [source, replacement]

        try await Task.sleep(
            nanoseconds: UInt64((SpaceSidebarRenderPolicy.completionDelay + 0.15) * 1_000_000_000)
        )

        let activeSpaceId = try XCTUnwrap(windowState.currentSpaceId)
        XCTAssertTrue(browserManager.tabManager.spaces.contains { $0.id == activeSpaceId })
        XCTAssertNotEqual(activeSpaceId, staleDestination.id)
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
    }
}
