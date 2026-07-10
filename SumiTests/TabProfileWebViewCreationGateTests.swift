import Combine
import Foundation
import XCTest

@testable import Sumi

@MainActor
final class TabProfileWebViewCreationGateTests: XCTestCase {
    func testDefersOnceAndSetsUpWebViewWhenProfileArrives() {
        let harness = TabProfileWebViewCreationGateHarness()
        let owner = harness.makeOwner()

        XCTAssertTrue(owner.deferCreationUntilProfileAvailable())

        XCTAssertEqual(harness.currentProfileUpdatesCallCount, 1)
        XCTAssertNotNil(harness.cancellable)

        XCTAssertTrue(owner.deferCreationUntilProfileAvailable())

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

        XCTAssertTrue(owner.deferCreationUntilProfileAvailable())
        harness.subject.send(Profile(name: "Ready"))
        drainMainRunLoop()

        XCTAssertEqual(harness.setupWebViewCallCount, 0)
        XCTAssertNotNil(harness.cancellable)
    }

    func testUsesInjectedCurrentProfileUpdatesWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let subject = PassthroughSubject<Profile?, Never>()
        var currentProfileUpdatesCallCount = 0
        let owner = TabProfileWebViewCreationGate(
            tab: tab,
            currentProfileUpdates: {
                currentProfileUpdatesCallCount += 1
                return subject.eraseToAnyPublisher()
            }
        )

        XCTAssertTrue(owner.deferCreationUntilProfileAvailable())

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(currentProfileUpdatesCallCount, 1)
        XCTAssertNotNil(tab.profileAwaitCancellable)
    }

    func testCannotDeferWithoutAProfileUpdateSource() {
        let harness = TabProfileWebViewCreationGateHarness()
        let owner = harness.makeOwner(currentProfileUpdates: { nil })

        XCTAssertFalse(owner.deferCreationUntilProfileAvailable())
        XCTAssertNil(harness.cancellable)
    }
}

@MainActor
private final class TabProfileWebViewCreationGateHarness {
    let subject = PassthroughSubject<Profile?, Never>()
    var currentProfileUpdatesCallCount = 0
    var cancellable: AnyCancellable?
    var hasCurrentWebView = false
    var setupWebViewCallCount = 0

    func makeOwner(
        currentProfileUpdates: (() -> AnyPublisher<Profile?, Never>?)? = nil
    ) -> TabProfileWebViewCreationGate {
        TabProfileWebViewCreationGate(
            currentProfileUpdates: { [weak self] in
                self?.currentProfileUpdatesCallCount += 1
                if let currentProfileUpdates {
                    return currentProfileUpdates()
                }
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
            ensureUntrackedNormalWebView: { [weak self] in
                self?.setupWebViewCallCount += 1
            }
        )
    }
}

@MainActor
private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
}
