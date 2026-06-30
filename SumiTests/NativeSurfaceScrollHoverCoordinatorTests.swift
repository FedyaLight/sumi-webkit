import XCTest

@testable import Sumi

@MainActor
final class NativeSurfaceScrollHoverCoordinatorTests: XCTestCase {
    func testPhaseScrollKeepsHoverSuppressedAcrossActivityRestore() async {
        let coordinator = NativeSurfaceScrollHoverCoordinator()

        coordinator.setScrolling(true, region: "sidebar")
        coordinator.notifyScrollActivity(region: "sidebar")
        await waitPastHoverRestoreDelay()

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        coordinator.setScrolling(false, region: "sidebar")
        await waitPastHoverRestoreDelay()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testTransientActivityRestoresHoverWhenNoPhaseScrollIsActive() async {
        let coordinator = NativeSurfaceScrollHoverCoordinator()

        coordinator.notifyScrollActivity(region: "sidebar")

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        await waitPastHoverRestoreDelay()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testResetCancelsPendingRestoreAndEnablesHover() async {
        let coordinator = NativeSurfaceScrollHoverCoordinator()

        coordinator.notifyScrollActivity(region: "sidebar")
        coordinator.reset()
        await waitPastHoverRestoreDelay()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testUnregisterScrollingRegionRestoresHoverAfterDelay() async {
        let coordinator = NativeSurfaceScrollHoverCoordinator()
        let token = coordinator.registerRegion("sidebar")

        coordinator.setScrolling(true, region: "sidebar")
        coordinator.unregisterRegion("sidebar", token: token)

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        await waitPastHoverRestoreDelay()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testStaleRegionTokenCannotClearReplacementRegion() async {
        let coordinator = NativeSurfaceScrollHoverCoordinator()
        let staleToken = coordinator.registerRegion("sidebar")

        coordinator.setScrolling(true, region: "sidebar")
        let replacementToken = coordinator.registerRegion("sidebar")
        coordinator.unregisterRegion("sidebar", token: staleToken)

        await waitPastHoverRestoreDelay()

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        coordinator.unregisterRegion("sidebar", token: replacementToken)
        await waitPastHoverRestoreDelay()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    private func waitPastHoverRestoreDelay() async {
        try? await Task.sleep(nanoseconds: 320_000_000)
    }
}
