import AppKit
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testMiniWindowAdapterSetStateCompletesAfterExactNativeSettlement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)
        let didMiniaturizeExpectation = expectation(
            description: "exact window did miniaturize"
        )
        let didMiniaturizeTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                didMiniaturizeExpectation.fulfill()
                return true
            }
        )
        let didMiniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                didMiniaturizeTrigger.fire()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(didMiniaturizeObserver)
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        var callbackError: Error?
        var callbackObservedSettlement = false
        let completionExpectation = expectation(
            description: "state transition completion"
        )
        adapter.setWindowState(
            .minimized,
            for: harness.extensionContext
        ) {
            callbackError = $0
            callbackObservedSettlement = didMiniaturizeTrigger.didFire
            completionExpectation.fulfill()
        }
        await fulfillment(
            of: [didMiniaturizeExpectation, completionExpectation],
            timeout: 5
        )

        XCTAssertTrue(didMiniaturizeTrigger.didFire)
        XCTAssertTrue(callbackObservedSettlement)
        XCTAssertNil(callbackError)
        XCTAssertTrue(target.window.isMiniaturized)
        XCTAssertEqual(
            adapter.windowState(for: harness.extensionContext),
            .minimized
        )
    }

    func testMiniWindowAdapterStateSupersessionSequencesNativeSettlement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)

        let didMiniaturizeExpectation = expectation(
            description: "superseded native minimize settled"
        )
        let didMiniaturizeTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                didMiniaturizeExpectation.fulfill()
                return true
            }
        )
        let didMiniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                didMiniaturizeTrigger.fire()
            }
        }
        let didDeminiaturizeExpectation = expectation(
            description: "replacement native normal state settled"
        )
        let didDeminiaturizeTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                didDeminiaturizeExpectation.fulfill()
                return true
            }
        )
        let didDeminiaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                didDeminiaturizeTrigger.fire()
            }
        }

        var replacementError: Error?
        var replacementCompletionCount = 0
        var replacementObservedMiniaturize = false
        var replacementObservedDeminiaturize = false
        let replacementCompletion = expectation(
            description: "replacement state completion"
        )
        replacementCompletion.assertForOverFulfill = true
        let supersessionTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                adapter.setWindowState(
                    .normal,
                    for: harness.extensionContext
                ) {
                    replacementError = $0
                    replacementCompletionCount += 1
                    replacementObservedMiniaturize =
                        didMiniaturizeTrigger.didFire
                    replacementObservedDeminiaturize =
                        didDeminiaturizeTrigger.didFire
                    replacementCompletion.fulfill()
                }
                return true
            }
        )
        let willMiniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                supersessionTrigger.fire()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(willMiniaturizeObserver)
            NotificationCenter.default.removeObserver(didMiniaturizeObserver)
            NotificationCenter.default.removeObserver(
                didDeminiaturizeObserver
            )
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        var supersededError: Error?
        var supersededCompletionCount = 0
        let supersededCompletion = expectation(
            description: "superseded state completion"
        )
        supersededCompletion.assertForOverFulfill = true
        adapter.setWindowState(
            .minimized,
            for: harness.extensionContext
        ) {
            supersededError = $0
            supersededCompletionCount += 1
            supersededCompletion.fulfill()
        }
        await fulfillment(
            of: [
                supersededCompletion,
                didMiniaturizeExpectation,
                didDeminiaturizeExpectation,
                replacementCompletion,
            ],
            timeout: 5
        )

        XCTAssertTrue(supersessionTrigger.didFire)
        XCTAssertEqual(supersededCompletionCount, 1)
        assertExtensionBridgeCallbackError(
            supersededError,
            equals: .miniWindowStateTransitionSuperseded
        )
        XCTAssertEqual(replacementCompletionCount, 1)
        XCTAssertNil(replacementError)
        XCTAssertTrue(replacementObservedMiniaturize)
        XCTAssertTrue(replacementObservedDeminiaturize)
        XCTAssertFalse(target.window.isMiniaturized)
        XCTAssertEqual(
            adapter.windowState(for: harness.extensionContext),
            .normal
        )
    }

    func testMiniWindowAdapterCloseInvalidatesActiveStateExactlyOnce()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let targetReceipt = try XCTUnwrap(
            auxiliaryWindows.sessions.receipt(for: target)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)

        let willCloseExpectation = expectation(
            description: "exact window began closing"
        )
        let willCloseTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                willCloseExpectation.fulfill()
                return true
            }
        )
        let willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                willCloseTrigger.fire()
            }
        }
        let fullscreenTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: { true }
        )
        let fullscreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                fullscreenTrigger.fire()
            }
        }

        var closeError: Error?
        var closeCompletionCount = 0
        let closeCompletion = expectation(
            description: "close completion"
        )
        closeCompletion.assertForOverFulfill = true
        let closeTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                adapter.close(for: harness.extensionContext) {
                    closeError = $0
                    closeCompletionCount += 1
                    closeCompletion.fulfill()
                }
                return true
            }
        )
        let willMiniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                closeTrigger.fire()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(willMiniaturizeObserver)
            NotificationCenter.default.removeObserver(willCloseObserver)
            NotificationCenter.default.removeObserver(fullscreenObserver)
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        var transitionError: Error?
        var transitionCompletionCount = 0
        let transitionCompletion = expectation(
            description: "invalidated transition completion"
        )
        transitionCompletion.assertForOverFulfill = true
        var reentrantError: Error?
        var reentrantCompletionCount = 0
        let reentrantCompletion = expectation(
            description: "retired adapter rejects reentrant state"
        )
        reentrantCompletion.assertForOverFulfill = true
        adapter.setWindowState(
            .minimized,
            for: harness.extensionContext
        ) {
            transitionError = $0
            transitionCompletionCount += 1
            adapter.setWindowState(
                .fullscreen,
                for: harness.extensionContext
            ) {
                reentrantError = $0
                reentrantCompletionCount += 1
                reentrantCompletion.fulfill()
            }
            transitionCompletion.fulfill()
        }
        await fulfillment(
            of: [
                transitionCompletion,
                reentrantCompletion,
                willCloseExpectation,
                closeCompletion,
            ],
            timeout: 5
        )

        XCTAssertTrue(closeTrigger.didFire)
        XCTAssertTrue(willCloseTrigger.didFire)
        XCTAssertEqual(transitionCompletionCount, 1)
        assertExtensionBridgeCallbackError(
            transitionError,
            equals: .miniWindowStateTransitionInvalidated
        )
        XCTAssertEqual(reentrantCompletionCount, 1)
        assertExtensionBridgeCallbackError(
            reentrantError,
            equals: .miniWindowUnavailable(operation: .setWindowState)
        )
        XCTAssertFalse(fullscreenTrigger.didFire)
        XCTAssertEqual(closeCompletionCount, 1)
        XCTAssertNil(closeError)
        XCTAssertNil(auxiliaryWindows.sessions.session(for: targetReceipt))
    }
}
