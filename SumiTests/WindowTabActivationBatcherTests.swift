@testable import Sumi
import XCTest

@MainActor
final class WindowTabActivationBatcherTests: XCTestCase {
    func testSameWindowRequestsFlushLatestActivationOnce() async {
        let batcher = WindowTabActivationBatcher()
        let windowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()
        var flushedActivations: [FlushedActivation] = []
        let flushExpectation = expectation(description: "Flushes one activation")
        flushExpectation.expectedFulfillmentCount = 1

        let recordFlush: @MainActor (UUID, WindowTabActivationBatcher.Activation) -> Void = { windowId, activation in
            flushedActivations.append(FlushedActivation(windowId: windowId, activation: activation))
            flushExpectation.fulfill()
        }

        batcher.requestActivation(
            tabId: firstTabId,
            in: windowId,
            loadPolicy: .immediate,
            onFlush: recordFlush
        )
        batcher.requestActivation(
            tabId: secondTabId,
            in: windowId,
            loadPolicy: .deferred,
            onFlush: recordFlush
        )

        await fulfillment(of: [flushExpectation], timeout: 1.0)
        await drainScheduledFlushWork()

        XCTAssertEqual(
            flushedActivations,
            [
                FlushedActivation(
                    windowId: windowId,
                    tabId: secondTabId,
                    loadPolicy: .deferred
                ),
            ]
        )
    }

    func testDifferentWindowRequestsFlushIndependently() async {
        let batcher = WindowTabActivationBatcher()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()
        var flushedActivations: [FlushedActivation] = []
        let flushExpectation = expectation(description: "Flushes both windows")
        flushExpectation.expectedFulfillmentCount = 2

        let recordFlush: @MainActor (UUID, WindowTabActivationBatcher.Activation) -> Void = { windowId, activation in
            flushedActivations.append(FlushedActivation(windowId: windowId, activation: activation))
            flushExpectation.fulfill()
        }

        batcher.requestActivation(
            tabId: firstTabId,
            in: firstWindowId,
            loadPolicy: .immediate,
            onFlush: recordFlush
        )
        batcher.requestActivation(
            tabId: secondTabId,
            in: secondWindowId,
            loadPolicy: .deferred,
            onFlush: recordFlush
        )

        await fulfillment(of: [flushExpectation], timeout: 1.0)

        XCTAssertEqual(flushedActivations.count, 2)
        XCTAssertTrue(
            flushedActivations.contains(
                FlushedActivation(
                    windowId: firstWindowId,
                    tabId: firstTabId,
                    loadPolicy: .immediate
                )
            )
        )
        XCTAssertTrue(
            flushedActivations.contains(
                FlushedActivation(
                    windowId: secondWindowId,
                    tabId: secondTabId,
                    loadPolicy: .deferred
                )
            )
        )
    }

    func testNewRequestAfterFlushSchedulesAnotherFlush() async {
        let batcher = WindowTabActivationBatcher()
        let windowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()
        var flushedActivations: [FlushedActivation] = []
        let firstFlushExpectation = expectation(description: "Flushes first activation")

        batcher.requestActivation(
            tabId: firstTabId,
            in: windowId,
            loadPolicy: .immediate
        ) { windowId, activation in
            flushedActivations.append(FlushedActivation(windowId: windowId, activation: activation))
            firstFlushExpectation.fulfill()
        }

        await fulfillment(of: [firstFlushExpectation], timeout: 1.0)

        let secondFlushExpectation = expectation(description: "Flushes second activation")
        batcher.requestActivation(
            tabId: secondTabId,
            in: windowId,
            loadPolicy: .deferred
        ) { windowId, activation in
            flushedActivations.append(FlushedActivation(windowId: windowId, activation: activation))
            secondFlushExpectation.fulfill()
        }

        await fulfillment(of: [secondFlushExpectation], timeout: 1.0)

        XCTAssertEqual(
            flushedActivations,
            [
                FlushedActivation(
                    windowId: windowId,
                    tabId: firstTabId,
                    loadPolicy: .immediate
                ),
                FlushedActivation(
                    windowId: windowId,
                    tabId: secondTabId,
                    loadPolicy: .deferred
                ),
            ]
        )
    }

    private func drainScheduledFlushWork() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }
}

private struct FlushedActivation: Equatable {
    let windowId: UUID
    let tabId: UUID
    let loadPolicy: TabSelectionLoadPolicy

    init(
        windowId: UUID,
        activation: WindowTabActivationBatcher.Activation
    ) {
        self.init(
            windowId: windowId,
            tabId: activation.tabId,
            loadPolicy: activation.loadPolicy
        )
    }

    init(
        windowId: UUID,
        tabId: UUID,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        self.windowId = windowId
        self.tabId = tabId
        self.loadPolicy = loadPolicy
    }
}
