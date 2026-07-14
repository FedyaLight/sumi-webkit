import AppKit
import XCTest

@testable import Sumi

@MainActor
final class AppTerminationFinalizerTests: XCTestCase {
    func testNoConfirmationReturnsTerminateLaterAndRepliesAfterFallbackFinalize() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        let fallbackSaved = expectation(description: "fallback persistence saved")
        let terminationReplied = expectation(description: "termination reply delivered")
        var events: [String] = []
        appDelegate.fallbackPersistenceSave = {
            events.append("fallback-save")
            fallbackSaved.fulfill()
        }
        appDelegate.terminationReply = { _, shouldTerminate in
            events.append("reply:\(shouldTerminate)")
            terminationReplied.fulfill()
        }

        let terminateReply = appDelegate.applicationShouldTerminate(.shared)

        XCTAssertEqual(terminateReply, .terminateLater)
        XCTAssertTrue(events.isEmpty)
        await fulfillment(of: [fallbackSaved, terminationReplied], timeout: 2)
        XCTAssertEqual(events, ["fallback-save", "reply:true"])
    }

    func testConfirmedFlowDoesNotReplyBeforeAsyncCleanupCompletes() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        let cleanupGate = TerminationTestGate()
        let finalizationStarted = expectation(description: "termination finalization started")
        let terminationReplied = expectation(description: "termination reply delivered")
        let lease = RecordingTerminationLease(
            finalizationGate: cleanupGate,
            onFinalizationStarted: { finalizationStarted.fulfill() }
        )
        let coordinator = RecordingTerminationCoordinator(lease: lease)
        var replies: [Bool] = []
        appDelegate.terminationCoordinator = coordinator
        appDelegate.fallbackPersistenceSave = {}
        appDelegate.terminationReply = { _, shouldTerminate in
            replies.append(shouldTerminate)
            terminationReplied.fulfill()
        }

        // This is the exact post-confirmation path used by both the sheet and
        // modal fallback once the user chooses Quit.
        appDelegate.beginTerminationFinalization(for: .shared)
        XCTAssertEqual(coordinator.acquireCallCount, 1)
        await fulfillment(of: [finalizationStarted], timeout: 2)

        XCTAssertTrue(replies.isEmpty)
        cleanupGate.open()
        await fulfillment(of: [terminationReplied], timeout: 2)
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(lease.finalizationCallCount, 1)
    }

    func testDuplicateQuitJoinsOneInFlightFinalizeAndRepliesOnce() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        let cleanupGate = TerminationTestGate()
        let finalizationStarted = expectation(description: "termination finalization started")
        let terminationReplied = expectation(description: "termination reply delivered")
        let lease = RecordingTerminationLease(
            finalizationGate: cleanupGate,
            onFinalizationStarted: { finalizationStarted.fulfill() }
        )
        let coordinator = RecordingTerminationCoordinator(lease: lease)
        var fallbackSaveCount = 0
        var replies: [Bool] = []
        appDelegate.terminationCoordinator = coordinator
        appDelegate.fallbackPersistenceSave = { fallbackSaveCount += 1 }
        appDelegate.terminationReply = { _, shouldTerminate in
            replies.append(shouldTerminate)
            terminationReplied.fulfill()
        }

        let first = appDelegate.applicationShouldTerminate(.shared)
        let duplicate = appDelegate.applicationShouldTerminate(.shared)
        await fulfillment(of: [finalizationStarted], timeout: 2)

        XCTAssertEqual(first, .terminateLater)
        XCTAssertEqual(duplicate, .terminateLater)
        XCTAssertEqual(fallbackSaveCount, 0)
        XCTAssertTrue(replies.isEmpty)

        cleanupGate.open()
        await fulfillment(of: [terminationReplied], timeout: 2)
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(coordinator.prepareCallCount, 1)
        XCTAssertEqual(coordinator.acquireCallCount, 1)
        XCTAssertEqual(lease.finalizationCallCount, 1)
    }

    func testTimeoutRepliesExactlyOnceAndLateFinalizeCannotReplyAgain() async {
        let timeoutWaitStarted = expectation(description: "termination timeout wait started")
        let timeoutGate = TerminationTestGate(
            onWaitStarted: { timeoutWaitStarted.fulfill() }
        )
        let finalizeGate = TerminationTestGate()
        let finalizationStarted = expectation(description: "termination finalization started")
        let finalizationCompleted = expectation(description: "late finalization completed")
        let terminationReplied = expectation(description: "termination reply delivered")
        var replyReasons: [AppTerminationFinalizer.ReplyReason] = []
        var replies: [Bool] = []
        var finalizeStarted = false
        var finalizeCompleted = false
        let finalizer = AppTerminationFinalizer(
            waitForTimeout: { await timeoutGate.wait() },
            observeReply: { replyReasons.append($0) }
        )

        XCTAssertTrue(finalizer.begin(
            finalize: {
                finalizeStarted = true
                finalizationStarted.fulfill()
                await finalizeGate.wait()
                finalizeCompleted = true
                finalizationCompleted.fulfill()
            },
            reply: {
                replies.append($0)
                terminationReplied.fulfill()
            }
        ))
        await fulfillment(of: [finalizationStarted, timeoutWaitStarted], timeout: 2)
        XCTAssertTrue(finalizeStarted)
        XCTAssertTrue(replies.isEmpty)

        timeoutGate.open()
        await fulfillment(of: [terminationReplied], timeout: 2)
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(replyReasons, [.timedOut])
        XCTAssertFalse(finalizeCompleted)

        finalizeGate.open()
        await fulfillment(of: [finalizationCompleted], timeout: 2)
        XCTAssertTrue(finalizeCompleted)
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(replyReasons, [.timedOut])
    }
}

@MainActor
private final class TerminationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private let onWaitStarted: @MainActor () -> Void
    private(set) var isOpen = false

    init(onWaitStarted: @escaping @MainActor () -> Void = {}) {
        self.onWaitStarted = onWaitStarted
    }

    func wait() async {
        guard isOpen == false else { return }
        onWaitStarted()
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        guard isOpen == false else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class RecordingTerminationCoordinator: BrowserTerminationCoordinating {
    private let lease: RecordingTerminationLease
    private(set) var prepareCallCount = 0
    private(set) var acquireCallCount = 0

    init(lease: RecordingTerminationLease) {
        self.lease = lease
    }

    func prepareForTermination() {
        prepareCallCount += 1
    }

    func acquireFinalizationLease() -> (any BrowserTerminationFinalizing)? {
        acquireCallCount += 1
        return lease
    }
}

@MainActor
private final class RecordingTerminationLease: BrowserTerminationFinalizing {
    private let finalizationGate: TerminationTestGate
    private let onFinalizationStarted: @MainActor () -> Void
    private(set) var finalizationCallCount = 0

    init(
        finalizationGate: TerminationTestGate,
        onFinalizationStarted: @escaping @MainActor () -> Void = {}
    ) {
        self.finalizationGate = finalizationGate
        self.onFinalizationStarted = onFinalizationStarted
    }

    func finalizeTermination() async {
        finalizationCallCount += 1
        onFinalizationStarted()
        await finalizationGate.wait()
    }
}
