import Combine
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class TabProfileWebViewCreationGateTests: XCTestCase {
    func testDefersOnceAndSetsUpWebViewWhenProfileArrives() {
        let harness = TabProfileWebViewCreationGateHarness()
        let owner = harness.makeOwner()

        owner.deferCreationUntilProfileAvailable()

        XCTAssertEqual(harness.currentProfileUpdatesCallCount, 1)
        XCTAssertNotNil(harness.cancellable)

        owner.deferCreationUntilProfileAvailable()

        XCTAssertEqual(harness.currentProfileUpdatesCallCount, 1)

        harness.subject.send(nil)
        drainMainRunLoop()

        XCTAssertEqual(harness.setupWebViewCallCount, 0)
        XCTAssertNotNil(harness.cancellable)

        harness.subject.send(Profile(name: "Ready"))
        drainMainRunLoop()

        XCTAssertEqual(harness.setupWebViewCallCount, 1)
        XCTAssertNil(harness.cancellable)

        harness.subject.send(Profile(name: "Ignored"))
        drainMainRunLoop()

        XCTAssertEqual(harness.setupWebViewCallCount, 1)
    }

    func testProfileArrivalDoesNotConsumeGateWhenWebViewAlreadyExists() {
        let harness = TabProfileWebViewCreationGateHarness()
        let owner = harness.makeOwner()

        harness.hasCurrentWebView = true

        owner.deferCreationUntilProfileAvailable()
        harness.subject.send(Profile(name: "Ready"))
        drainMainRunLoop()

        XCTAssertEqual(harness.setupWebViewCallCount, 0)
        XCTAssertNotNil(harness.cancellable)
    }
}

@MainActor
private final class TabProfileWebViewCreationGateHarness {
    let subject = PassthroughSubject<Profile?, Never>()
    var currentProfileUpdatesCallCount = 0
    var cancellable: AnyCancellable?
    var hasCurrentWebView = false
    var setupWebViewCallCount = 0

    func makeOwner() -> TabProfileWebViewCreationGate {
        TabProfileWebViewCreationGate(
            dependencies: TabProfileWebViewCreationGate.Dependencies(
                currentProfileUpdates: { [weak self] in
                    self?.currentProfileUpdatesCallCount += 1
                    return self?.subject.eraseToAnyPublisher()
                },
                currentProfileAwaitCancellable: { [weak self] in
                    self?.cancellable
                },
                setCurrentProfileAwaitCancellable: { [weak self] cancellable in
                    self?.cancellable = cancellable
                },
                hasCurrentWebView: { [weak self] in
                    self?.hasCurrentWebView == true
                },
                setupWebView: { [weak self] in
                    self?.setupWebViewCallCount += 1
                }
            )
        )
    }
}

@MainActor
private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
}
