import Combine
import XCTest

@testable import Sumi

@MainActor
final class TabStructureEventBusTests: XCTestCase {
    func testTypedPublishersReceiveOnlyTheirEvents() {
        let bus = TabStructureEventBus()
        var structureChangedCount = 0
        var livePageResidenceChangedCount = 0
        var folderExpansionChangedCount = 0
        var initialDataLoadedCount = 0
        let structureCancellable = bus.structureChangedPublisher.sink {
            structureChangedCount += 1
        }
        let initialDataCancellable = bus.initialDataLoadedPublisher.sink {
            initialDataLoadedCount += 1
        }
        let expansionCancellable = bus.folderExpansionChangesPublisher.sink { _ in
            folderExpansionChangedCount += 1
        }
        let residenceCancellable = bus.livePageResidenceChangesPublisher.sink {
            _ in livePageResidenceChangedCount += 1
        }

        bus.publishInitialDataLoaded()
        bus.publishStructureChanged()
        bus.publishStructureChanged()
        bus.publishLivePageResidenceChanged(LivePageResidenceScope(
            windowID: UUID(),
            spaceID: UUID()
        ))
        bus.publishFolderExpansionChanged(
            TabFolderExpansionChange(
                revision: 3,
                spaceID: UUID(),
                expansionByFolderID: [UUID(): true]
            )
        )

        XCTAssertEqual(structureChangedCount, 2)
        XCTAssertEqual(livePageResidenceChangedCount, 1)
        XCTAssertEqual(folderExpansionChangedCount, 1)
        XCTAssertEqual(initialDataLoadedCount, 1)
        withExtendedLifetime((
            structureCancellable,
            residenceCancellable,
            initialDataCancellable,
            expansionCancellable
        )) {}
    }

    func testGeneralPublisherPreservesEventOrder() {
        let bus = TabStructureEventBus()
        var events: [TabStructureEvent] = []
        let cancellable = bus.publisher.sink { events.append($0) }

        bus.publishStructureChanged()
        bus.publishInitialDataLoaded()

        XCTAssertEqual(events, [.structureChanged(.all), .initialDataLoaded])
        withExtendedLifetime(cancellable) {}
    }

    func testInitialDataLoadedPublisherReplaysReadinessToLateSubscriber() {
        let bus = TabStructureEventBus()
        bus.publishInitialDataLoaded()
        var initialDataLoadedCount = 0

        let cancellable = bus.initialDataLoadedPublisher.sink {
            initialDataLoadedCount += 1
        }

        XCTAssertEqual(initialDataLoadedCount, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testResetInitialDataLoadedStopsReplayUntilNextCompletion() {
        let bus = TabStructureEventBus()
        bus.publishInitialDataLoaded()
        bus.resetInitialDataLoaded()
        var initialDataLoadedCount = 0
        let cancellable = bus.initialDataLoadedPublisher.sink {
            initialDataLoadedCount += 1
        }

        XCTAssertEqual(initialDataLoadedCount, 0)
        bus.publishInitialDataLoaded()
        XCTAssertEqual(initialDataLoadedCount, 1)
        withExtendedLifetime(cancellable) {}
    }
}
