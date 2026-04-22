import XCTest

@testable import Sumi

final class RuntimeStateCoalescerTests: XCTestCase {
    func testSameTabUpdatesCollapseToLatestPayload() async throws {
        let recorder = RuntimeStateBatchRecorder()
        let coalescer = RuntimeStateCoalescer(
            debounceNanoseconds: 1_000_000_000,
            persistBatch: { states in
                await recorder.record(states)
            }
        )
        let tabID = UUID()

        coalescer.enqueue(makeRuntimeState(id: tabID, urlString: "https://example.com/first", name: "First"))
        coalescer.enqueue(makeRuntimeState(id: tabID, urlString: "https://example.com/latest", name: "Latest"))

        let flushedCount = await coalescer.flushImmediately()
        let batches = await recorder.allBatches()

        XCTAssertEqual(flushedCount, 1)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.count, 1)
        XCTAssertEqual(batches.first?.first?.id, tabID)
        XCTAssertEqual(batches.first?.first?.urlString, "https://example.com/latest")
        XCTAssertEqual(batches.first?.first?.name, "Latest")
    }

    func testMultipleTabsPersistInOneCoalescedFlush() async throws {
        let recorder = RuntimeStateBatchRecorder()
        let coalescer = RuntimeStateCoalescer(
            debounceNanoseconds: 10_000_000,
            persistBatch: { states in
                await recorder.record(states)
            }
        )
        let firstID = UUID()
        let secondID = UUID()

        coalescer.enqueue(makeRuntimeState(id: firstID, urlString: "https://example.com/one", name: "One"))
        coalescer.enqueue(makeRuntimeState(id: secondID, urlString: "https://example.com/two", name: "Two"))

        let batches = try await waitForBatches(count: 1, recorder: recorder)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(Set(batches[0].map(\.id)), [firstID, secondID])
    }

    func testForceFlushPersistsWithoutWaitingForDebounce() async throws {
        let recorder = RuntimeStateBatchRecorder()
        let coalescer = RuntimeStateCoalescer(
            debounceNanoseconds: 60_000_000_000,
            persistBatch: { states in
                await recorder.record(states)
            }
        )
        let tabID = UUID()

        coalescer.enqueue(makeRuntimeState(id: tabID, urlString: "https://example.com/force", name: "Force"))
        let flushedCount = await coalescer.flushImmediately()
        let batches = await recorder.allBatches()

        XCTAssertEqual(flushedCount, 1)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.first?.id, tabID)
    }

    func testShutdownFlushDrainsPendingPayloads() async throws {
        let recorder = RuntimeStateBatchRecorder()
        let coalescer = RuntimeStateCoalescer(
            debounceNanoseconds: 60_000_000_000,
            persistBatch: { states in
                await recorder.record(states)
            }
        )
        let tabID = UUID()

        coalescer.enqueue(makeRuntimeState(id: tabID, urlString: "https://example.com/shutdown", name: "Shutdown"))
        let flushedCount = await coalescer.shutdownAndFlush()
        let batches = await recorder.allBatches()

        XCTAssertEqual(flushedCount, 1)
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.first?.id, tabID)
    }

    private func makeRuntimeState(
        id: UUID,
        urlString: String,
        name: String,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) -> TabSnapshotRepository.RuntimeTabState {
        TabSnapshotRepository.RuntimeTabState(
            id: id,
            urlString: urlString,
            currentURLString: urlString,
            name: name,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
    }

    private func waitForBatches(
        count expectedCount: Int,
        recorder: RuntimeStateBatchRecorder
    ) async throws -> [[TabSnapshotRepository.RuntimeTabState]] {
        for _ in 0..<50 {
            let batches = await recorder.allBatches()
            if batches.count >= expectedCount {
                return batches
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let batches = await recorder.allBatches()
        XCTFail("Timed out waiting for \(expectedCount) runtime-state batch(es); found \(batches.count)")
        return batches
    }
}

private actor RuntimeStateBatchRecorder {
    private var batches: [[TabSnapshotRepository.RuntimeTabState]] = []

    func record(_ states: [TabSnapshotRepository.RuntimeTabState]) {
        batches.append(states)
    }

    func allBatches() -> [[TabSnapshotRepository.RuntimeTabState]] {
        batches
    }
}
