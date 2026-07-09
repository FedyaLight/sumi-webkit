import Combine
import XCTest

@testable import Sumi

/// Smoke coverage for architecture hub wiring (composition root + event bus).
@MainActor
final class ArchitectureHubMetricsSmokeTests: XCTestCase {
    func testTabStructureEventBusPublishesStructureChanged() {
        let bus = BrowserCompositionRoot.makeTabStructureEventBus()
        var received = false
        let cancellable = bus.structureChangedPublisher.sink { _ in
            received = true
        }

        bus.publishStructureChanged()

        XCTAssertTrue(received)
        _ = cancellable
    }

    func testCompositionRootMakeTabStructureEventBusReturnsFreshBus() {
        let first = BrowserCompositionRoot.makeTabStructureEventBus()
        let second = BrowserCompositionRoot.makeTabStructureEventBus()
        XCTAssertFalse(first === second)
    }
}
