import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundRuntimeStateOwnerTests: XCTestCase {
    func testNoBackgroundContentDoesNotStartWake() async throws {
        let owner = ExtensionBackgroundRuntimeStateOwner()
        var didLoadBackground = false
        var didRecordMetric = false

        let didWake = try await owner.ensureBackgroundAvailableIfRequired(
            wakeKey: "profile:extension",
            hasBackgroundContent: false,
            reason: .install,
            trace: { _ in /* no-op */ },
            loadBackgroundContent: {
                didLoadBackground = true
            },
            recordWakeMetric: { _, _, _ in
                didRecordMetric = true
            }
        )

        XCTAssertFalse(didWake)
        XCTAssertFalse(didLoadBackground)
        XCTAssertFalse(didRecordMetric)
        XCTAssertEqual(owner.state(for: "profile:extension"), .neverLoaded)
    }

    func testConcurrentWakeAwaitsInFlightTask() async throws {
        let owner = ExtensionBackgroundRuntimeStateOwner()
        let wakeKey = "profile:extension"
        let wakeStarted = expectation(description: "background wake started")
        var releaseWake: CheckedContinuation<Void, Never>?
        var wakeCount = 0
        var metricFailures: [Bool] = []

        let firstWake = Task { @MainActor in
            try await owner.ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .nativeMessaging,
                trace: { _ in /* no-op */ },
                loadBackgroundContent: {
                    wakeCount += 1
                    wakeStarted.fulfill()
                    await withCheckedContinuation { continuation in
                        releaseWake = continuation
                    }
                },
                recordWakeMetric: { _, _, didFail in
                    metricFailures.append(didFail)
                }
            )
        }

        await fulfillment(of: [wakeStarted], timeout: 1.0)
        XCTAssertEqual(owner.state(for: wakeKey), .wakeInFlight)

        let secondWake = Task { @MainActor in
            try await owner.ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .nativeMessaging,
                trace: { _ in /* no-op */ },
                loadBackgroundContent: {
                    XCTFail("In-flight wake should be reused")
                },
                recordWakeMetric: { _, _, didFail in
                    metricFailures.append(didFail)
                }
            )
        }

        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertEqual(wakeCount, 1)

        releaseWake?.resume()
        let firstDidWake = try await firstWake.value
        let secondDidWake = try await secondWake.value
        XCTAssertTrue(firstDidWake)
        XCTAssertFalse(secondDidWake)
        XCTAssertEqual(owner.state(for: wakeKey), .loaded)
        XCTAssertEqual(metricFailures, [false])
    }

    func testFailedWakeMarksLoadFailedAndCanRetry() async throws {
        enum TestError: Error {
            case failed
        }

        let owner = ExtensionBackgroundRuntimeStateOwner()
        let wakeKey = "profile:extension"
        var metricFailures: [Bool] = []

        do {
            _ = try await owner.ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .install,
                trace: { _ in /* no-op */ },
                loadBackgroundContent: {
                    throw TestError.failed
                },
                recordWakeMetric: { _, _, didFail in
                    metricFailures.append(didFail)
                }
            )
            XCTFail("Wake should throw")
        } catch TestError.failed {
            XCTAssertEqual(owner.state(for: wakeKey), .loadFailed)
        }

        let didWake = try await owner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: true,
            reason: .enable,
            trace: { _ in /* no-op */ },
            loadBackgroundContent: { /* no-op */ },
            recordWakeMetric: { _, _, didFail in
                metricFailures.append(didFail)
            }
        )

        XCTAssertTrue(didWake)
        XCTAssertEqual(owner.state(for: wakeKey), .loaded)
        XCTAssertEqual(metricFailures, [true, false])
    }

    func testSupersededWakeCannotCommitStateOrMetricsAfterAwait() async {
        let owner = ExtensionBackgroundRuntimeStateOwner()
        let wakeKey = "profile:extension"
        let wakeStarted = expectation(description: "background wake started")
        var releaseWake: CheckedContinuation<Void, Never>?
        var isCurrent = true
        var metricFailures: [Bool] = []

        let wake = Task { @MainActor in
            try await owner.ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .nativeMessaging,
                trace: { _ in /* no-op */ },
                isCurrent: { isCurrent },
                loadBackgroundContent: {
                    wakeStarted.fulfill()
                    await withCheckedContinuation { continuation in
                        releaseWake = continuation
                    }
                },
                recordWakeMetric: { _, _, didFail in
                    metricFailures.append(didFail)
                }
            )
        }

        await fulfillment(of: [wakeStarted], timeout: 1.0)
        isCurrent = false
        releaseWake?.resume()

        do {
            _ = try await wake.value
            XCTFail("Superseded wake must fail closed")
        } catch is CancellationError {
            // Expected: supersession is not a background-load failure.
        } catch {
            XCTFail("Unexpected wake error: \(error)")
        }

        XCTAssertEqual(owner.state(for: wakeKey), .neverLoaded)
        XCTAssertEqual(metricFailures, [])
    }

    func testCurrentWakeSupersedesStaleInFlightWakeForSameKey() async throws {
        let owner = ExtensionBackgroundRuntimeStateOwner()
        let wakeKey = "profile:extension"
        let staleWakeStarted = expectation(description: "stale wake started")
        var releaseStaleWake: CheckedContinuation<Void, Never>?
        var staleIsCurrent = true
        var completedWakes: [String] = []

        let staleWake = Task { @MainActor in
            try await owner.ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .nativeMessaging,
                trace: { _ in /* no-op */ },
                isCurrent: { staleIsCurrent },
                loadBackgroundContent: {
                    staleWakeStarted.fulfill()
                    await withCheckedContinuation { continuation in
                        releaseStaleWake = continuation
                    }
                },
                recordWakeMetric: { _, _, _ in
                    completedWakes.append("stale")
                }
            )
        }

        await fulfillment(of: [staleWakeStarted], timeout: 1.0)
        staleIsCurrent = false

        let currentDidWake = try await owner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: true,
            reason: .nativeMessaging,
            trace: { _ in /* no-op */ },
            isCurrent: { true },
            loadBackgroundContent: { /* no-op */ },
            recordWakeMetric: { _, _, didFail in
                XCTAssertFalse(didFail)
                completedWakes.append("current")
            }
        )
        XCTAssertTrue(currentDidWake)

        releaseStaleWake?.resume()
        do {
            _ = try await staleWake.value
            XCTFail("Stale in-flight wake must not complete as current")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected stale wake error: \(error)")
        }

        XCTAssertEqual(owner.state(for: wakeKey), .loaded)
        XCTAssertEqual(completedWakes, ["current"])
    }
}
