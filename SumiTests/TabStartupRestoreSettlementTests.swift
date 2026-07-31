@testable import Sumi
import XCTest

@MainActor
extension TabStartupRestoreLifecycleTests {
    func testStructuralSettlementWaitsForInitialDataLoad() async {
        let lifecycle = TabStartupRestoreLifecycle(
            eventBus: TabStructureEventBus()
        )
        var startCount = 0
        let settlement = Task { @MainActor in
            await lifecycle.waitUntilInitialDataLoaded {
                startCount += 1
                return true
            }
        }
        await Task.yield()

        XCTAssertFalse(lifecycle.hasLoadedInitialData)
        XCTAssertEqual(startCount, 1)

        lifecycle.markLoadFinished()
        let didSettle = await settlement.value
        XCTAssertTrue(didSettle)
        XCTAssertTrue(lifecycle.hasLoadedInitialData)
    }

    func testStructuralSettlementFailsClosedWhenRestoreCannotStart() async {
        let lifecycle = TabStartupRestoreLifecycle(
            eventBus: TabStructureEventBus()
        )

        let didSettle = await lifecycle.waitUntilInitialDataLoaded {
            false
        }

        XCTAssertFalse(didSettle)
        XCTAssertFalse(lifecycle.hasLoadedInitialData)
    }

    func testStructuralSettlementFailsClosedWhenWaitIsCancelled() async {
        let lifecycle = TabStartupRestoreLifecycle(
            eventBus: TabStructureEventBus()
        )
        let settlement = Task { @MainActor in
            await lifecycle.waitUntilInitialDataLoaded {
                true
            }
        }
        await Task.yield()

        settlement.cancel()

        let didSettle = await settlement.value
        XCTAssertFalse(didSettle)
        XCTAssertFalse(lifecycle.hasLoadedInitialData)
    }

    func testInitialDataSettlementCanResetForANewRestoreAttempt() async {
        let settlement = TabInitialDataSettlement()
        settlement.settle()
        settlement.reset()

        let didSettle = await settlement.wait {
            false
        }

        XCTAssertFalse(didSettle)
    }
}
