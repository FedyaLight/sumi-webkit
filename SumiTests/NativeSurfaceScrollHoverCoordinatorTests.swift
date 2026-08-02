import XCTest

@testable import Sumi

@MainActor
final class NativeSurfaceScrollHoverCoordinatorTests: XCTestCase {
    func testPhaseScrollKeepsHoverSuppressedUntilPhaseEnds() async {
        let coordinator = makeImmediateRestoreCoordinator()

        coordinator.setScrolling(true, region: "sidebar")
        await waitForScheduledRestore()

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        coordinator.setScrolling(false, region: "sidebar")
        await waitForScheduledRestore()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testResetCancelsPendingRestoreAndEnablesHover() async {
        let coordinator = makeImmediateRestoreCoordinator()

        coordinator.setScrolling(true, region: "sidebar")
        coordinator.reset()
        await waitForScheduledRestore()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testUnregisterScrollingRegionRestoresHoverAfterDelay() async {
        let coordinator = makeImmediateRestoreCoordinator()
        let token = coordinator.registerRegion("sidebar")

        coordinator.setScrolling(true, region: "sidebar")
        coordinator.unregisterRegion("sidebar", token: token)

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        await waitForScheduledRestore()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    func testStaleRegionTokenCannotClearReplacementRegion() async {
        let coordinator = makeImmediateRestoreCoordinator()
        let staleToken = coordinator.registerRegion("sidebar")

        coordinator.setScrolling(true, region: "sidebar")
        let replacementToken = coordinator.registerRegion("sidebar")
        coordinator.unregisterRegion("sidebar", token: staleToken)

        await waitForScheduledRestore()

        XCTAssertFalse(coordinator.hoverUpdatesEnabled)

        coordinator.unregisterRegion("sidebar", token: replacementToken)
        await waitForScheduledRestore()

        XCTAssertTrue(coordinator.hoverUpdatesEnabled)
    }

    private func makeImmediateRestoreCoordinator() -> NativeSurfaceScrollHoverCoordinator {
        NativeSurfaceScrollHoverCoordinator(
            hoverRestoreDelayNanoseconds: 0,
            sleepForNanoseconds: { _ in }
        )
    }

    private func waitForScheduledRestore() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}
