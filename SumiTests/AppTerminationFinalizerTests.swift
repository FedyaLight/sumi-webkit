import AppKit
import XCTest

@testable import Sumi

@MainActor
final class AppTerminationFinalizerTests: XCTestCase {
    func testNoConfirmationReturnsTerminateLaterAndRepliesAfterFallbackFinalize() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        var events: [String] = []
        appDelegate.fallbackPersistenceSave = {
            events.append("fallback-save")
        }
        appDelegate.terminationReply = { _, shouldTerminate in
            events.append("reply:\(shouldTerminate)")
        }

        let terminateReply = appDelegate.applicationShouldTerminate(.shared)

        XCTAssertEqual(terminateReply, .terminateLater)
        XCTAssertTrue(events.isEmpty)
        await waitUntil { events.count == 2 }
        XCTAssertEqual(events, ["fallback-save", "reply:true"])
    }

    func testConfirmedFlowDoesNotReplyBeforeAsyncCleanupCompletes() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        let cleanupGate = TerminationTestGate()
        let lease = RecordingTerminationLease(finalizationGate: cleanupGate)
        let coordinator = RecordingTerminationCoordinator(lease: lease)
        var replies: [Bool] = []
        appDelegate.terminationCoordinator = coordinator
        appDelegate.fallbackPersistenceSave = {}
        appDelegate.terminationReply = { _, shouldTerminate in
            replies.append(shouldTerminate)
        }

        // This is the exact post-confirmation path used by both the sheet and
        // modal fallback once the user chooses Quit.
        appDelegate.beginTerminationFinalization(for: .shared)
        XCTAssertEqual(coordinator.acquireCallCount, 1)
        await waitUntil { lease.finalizationStarted }

        XCTAssertTrue(replies.isEmpty)
        cleanupGate.open()
        await waitUntil { replies == [true] }
        XCTAssertEqual(lease.finalizationCallCount, 1)
    }

    func testDuplicateQuitJoinsOneInFlightFinalizeAndRepliesOnce() async {
        let finalizer = AppTerminationFinalizer(timeout: .seconds(5))
        let appDelegate = AppDelegate(terminationFinalizer: finalizer)
        let cleanupGate = TerminationTestGate()
        let lease = RecordingTerminationLease(finalizationGate: cleanupGate)
        let coordinator = RecordingTerminationCoordinator(lease: lease)
        var fallbackSaveCount = 0
        var replies: [Bool] = []
        appDelegate.terminationCoordinator = coordinator
        appDelegate.fallbackPersistenceSave = { fallbackSaveCount += 1 }
        appDelegate.terminationReply = { _, shouldTerminate in
            replies.append(shouldTerminate)
        }

        let first = appDelegate.applicationShouldTerminate(.shared)
        let duplicate = appDelegate.applicationShouldTerminate(.shared)
        await waitUntil { lease.finalizationStarted }

        XCTAssertEqual(first, .terminateLater)
        XCTAssertEqual(duplicate, .terminateLater)
        XCTAssertEqual(fallbackSaveCount, 0)
        XCTAssertTrue(replies.isEmpty)

        cleanupGate.open()
        await waitUntil { replies == [true] }
        await Task.yield()
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(coordinator.prepareCallCount, 1)
        XCTAssertEqual(coordinator.acquireCallCount, 1)
        XCTAssertEqual(lease.finalizationCallCount, 1)
    }

    func testTimeoutRepliesExactlyOnceAndLateFinalizeCannotReplyAgain() async {
        let timeoutGate = TerminationTestGate()
        let finalizeGate = TerminationTestGate()
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
                await finalizeGate.wait()
                finalizeCompleted = true
            },
            reply: { replies.append($0) }
        ))
        await waitUntil { finalizeStarted && timeoutGate.hasWaiter }
        XCTAssertTrue(replies.isEmpty)

        timeoutGate.open()
        await waitUntil { replies == [true] }
        XCTAssertEqual(replyReasons, [.timedOut])
        XCTAssertFalse(finalizeCompleted)

        finalizeGate.open()
        await waitUntil { finalizeCompleted }
        await Task.yield()
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(replyReasons, [.timedOut])
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while predicate() == false, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                XCTFail("Termination wait was cancelled")
                return
            }
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class TerminationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isOpen = false

    var hasWaiter: Bool { continuation != nil }

    func wait() async {
        guard isOpen == false else { return }
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
    private(set) var finalizationCallCount = 0
    private(set) var finalizationStarted = false

    init(finalizationGate: TerminationTestGate) {
        self.finalizationGate = finalizationGate
    }

    func finalizeTermination() async {
        finalizationCallCount += 1
        finalizationStarted = true
        await finalizationGate.wait()
    }
}
