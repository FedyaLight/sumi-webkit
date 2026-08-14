import XCTest

@testable import Sumi

@MainActor
final class PageLoadingIndicatorSessionTests: XCTestCase {
    func testSuccessorNavigationChainContinuesExistingPresentation() {
        let scheduler = TestPageLoadingIndicatorScheduler()
        var presentations: [Bool] = []
        let session = PageLoadingIndicatorSession(
            scheduler: scheduler,
            onPresentationChange: { presentations.append($0) }
        )

        session.observe(isLoading: true)
        for _ in 0..<3 {
            session.observe(isLoading: false)
            session.observe(isLoading: true)
        }
        scheduler.runAll()

        XCTAssertEqual(presentations, [true])
        XCTAssertTrue(session.isPresenting)
    }

    func testTerminalNavigationStopsAfterContinuationInterval() {
        let scheduler = TestPageLoadingIndicatorScheduler()
        var presentations: [Bool] = []
        let session = PageLoadingIndicatorSession(
            scheduler: scheduler,
            onPresentationChange: { presentations.append($0) }
        )

        session.observe(isLoading: true)
        session.observe(isLoading: false)

        XCTAssertEqual(presentations, [true])
        XCTAssertEqual(
            scheduler.delays,
            [PageLoadingIndicatorSession.defaultContinuationInterval]
        )

        scheduler.runAll()

        XCTAssertEqual(presentations, [true, false])
        XCTAssertFalse(session.isPresenting)
    }

    func testNavigationAfterSettlementStartsNewPresentation() {
        let scheduler = TestPageLoadingIndicatorScheduler()
        var presentations: [Bool] = []
        let session = PageLoadingIndicatorSession(
            scheduler: scheduler,
            onPresentationChange: { presentations.append($0) }
        )

        session.observe(isLoading: true)
        session.observe(isLoading: false)
        scheduler.runAll()
        session.observe(isLoading: true)

        XCTAssertEqual(presentations, [true, false, true])
    }

    func testInvalidationRejectsPendingSettlement() {
        let scheduler = TestPageLoadingIndicatorScheduler()
        var presentations: [Bool] = []
        let session = PageLoadingIndicatorSession(
            scheduler: scheduler,
            onPresentationChange: { presentations.append($0) }
        )

        session.observe(isLoading: true)
        session.observe(isLoading: false)
        session.invalidate()
        scheduler.runAll()

        XCTAssertEqual(presentations, [true])
        XCTAssertFalse(session.isPresenting)
    }
}

@MainActor
private final class TestPageLoadingIndicatorScheduler: PageLoadingIndicatorScheduling {
    private(set) var delays: [TimeInterval] = []
    private var scheduledWork: [@MainActor () -> Void] = []

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        delays.append(delay)
        scheduledWork.append(work)
    }

    func runAll() {
        while !scheduledWork.isEmpty {
            scheduledWork.removeFirst()()
        }
    }
}
