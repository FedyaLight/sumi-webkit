import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingBackgroundWakeOwnerTests: XCTestCase {
    func testScheduleDeduplicatesByWakeKey() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        let wakeStarted = expectation(description: "wake started")
        var releaseWake: CheckedContinuation<Void, Never>?
        var wakeCount = 0

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "first",
            wake: {
                wakeCount += 1
                wakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseWake = continuation
                }
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "second",
            wake: {
                XCTFail("Duplicate wake should be ignored")
            },
            logFailure: { _, _ in
                XCTFail("Duplicate wake should not log")
            }
        )

        await fulfillment(of: [wakeStarted], timeout: 1.0)
        XCTAssertEqual(wakeCount, 1)
        releaseWake?.resume()
        await owner.drainScheduledTasksForTests()
    }

    func testFinishedWakeIsRemovedAndCanBeScheduledAgain() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        var operations: [String] = []

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "first",
            wake: {
                operations.append("first")
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )
        await owner.drainScheduledTasksForTests()

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "second",
            wake: {
                operations.append("second")
            },
            logFailure: { _, _ in
                XCTFail("Wake should not fail")
            }
        )
        await owner.drainScheduledTasksForTests()

        XCTAssertEqual(operations, ["first", "second"])
    }

    func testCancelWakeTasksForExtensionCancelsOnlyMatchingWakeKeys() async {
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        let firstWakeStarted = expectation(description: "first wake started")
        let secondWakeStarted = expectation(description: "second wake started")
        var releaseFirstWake: CheckedContinuation<Void, Never>?
        var releaseSecondWake: CheckedContinuation<Void, Never>?

        owner.scheduleWake(
            wakeKey: "first-profile:first-extension",
            operation: "first",
            wake: {
                firstWakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirstWake = continuation
                }
            },
            logFailure: { _, _ in /* no-op */ }
        )
        owner.scheduleWake(
            wakeKey: "second-profile:second-extension",
            operation: "second",
            wake: {
                secondWakeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseSecondWake = continuation
                }
            },
            logFailure: { _, _ in /* no-op */ }
        )

        await fulfillment(
            of: [firstWakeStarted, secondWakeStarted],
            timeout: 1.0
        )
        owner.cancelWakeTasks(
            forExtensionId: "first-extension",
            wakeKeyBelongsToExtension: { wakeKey, extensionId in
                wakeKey.hasSuffix(":\(extensionId)")
            }
        )

        releaseFirstWake?.resume()
        releaseSecondWake?.resume()
        await owner.drainScheduledTasksForTests()
        XCTAssertTrue(owner.runtimeTasksForDrain().isEmpty)
    }

    func testFailureLoggerReceivesOperation() async {
        enum TestError: Error, Equatable {
            case failed
        }

        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        var loggedOperation: String?
        var didLogFailure = false

        owner.scheduleWake(
            wakeKey: "profile:extension",
            operation: "wake before sendMessage",
            wake: {
                throw TestError.failed
            },
            logFailure: { error, operation in
                XCTAssertEqual(error as? TestError, .failed)
                loggedOperation = operation
                didLogFailure = true
            }
        )

        await owner.drainScheduledTasksForTests()
        XCTAssertTrue(didLogFailure)
        XCTAssertEqual(loggedOperation, "wake before sendMessage")
    }
}

@available(macOS 15.5, *)
@MainActor
private extension ExtensionNativeMessagingBackgroundWakeOwner {
    func drainScheduledTasksForTests() async {
        while true {
            let tasks = runtimeTasksForDrain()
            guard tasks.isEmpty == false else { return }

            for task in tasks {
                await task.value
            }
        }
    }
}
