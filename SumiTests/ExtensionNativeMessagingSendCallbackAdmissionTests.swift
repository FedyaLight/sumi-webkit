import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Integration tests for typed callback-evidence admission on the WebKit
/// `sendMessage` native-messaging delegate callback, driven through the real
/// `ExtensionControllerDelegateBridge` against a live `ExtensionManager` with
/// the companion-application boundary modeled by a held fake adapter.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingSendCallbackAdmissionTests:
    ExtensionNativeMessagingAdmissionTestCase {
    // MARK: - 1. Exact current send is admitted end to end

    func testExactCurrentSendIsAdmittedAndRelays() async throws {
        let harness = try await makeHarness(name: "SendExact")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        adapter.completesImmediately = true
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let countersBefore = SumiNativeMessagingRuntimeCounters.snapshot()

        let result = await driveSendMessage(harness: harness)

        XCTAssertEqual(adapter.oneShotRequestCount, 1)
        XCTAssertNil(result.error)
        XCTAssertEqual((result.value as? [String: Bool])?["pong"], true)
        XCTAssertEqual(result.replyCalls, 1)
        let countersAfter = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(
            countersAfter.delegateSendMessageInvokedCount,
            countersBefore.delegateSendMessageInvokedCount + 1
        )
    }

    // MARK: - 2. Wrong controller fails closed before counters/wake/relay

    func testWrongControllerSendFailsClosedBeforeCountersWakeAndRelay() async throws {
        let harness = try await makeHarness(name: "SendWrongController")
        let foreignController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let countersBefore = SumiNativeMessagingRuntimeCounters.snapshot()

        let result = await driveSendMessage(
            harness: harness,
            controller: foreignController
        )

        assertIsStaleCallbackError(result.error)
        XCTAssertNil(result.value)
        XCTAssertEqual(result.replyCalls, 1)
        let countersAfter = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(
            countersAfter.delegateSendMessageInvokedCount,
            countersBefore.delegateSendMessageInvokedCount,
            "capture failure must not record delegate counters"
        )
        XCTAssertEqual(
            countersAfter.sendMessageCount,
            countersBefore.sendMessageCount,
            "capture failure must not reach the relay"
        )
        XCTAssertNil(
            harness.inspection.nativeMessaging.loadedRelay,
            "capture failure must not materialize the relay"
        )
        XCTAssertFalse(
            harness.inspection.nativeMessaging.hasLoadedWakeOwner,
            "capture failure must not create the background-wake owner"
        )
    }

    // MARK: - 4. Same-context rebind invalidates the send

    func testSameContextRebindDuringRelayInvalidatesSend() async throws {
        let harness = try await makeHarness(name: "SendSameContextRebind")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)

        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.oneShotRequestCount, 1)

        rebindSameContext(harness)
        adapter.completeHeldOneShotReplies(value: ["secret": true])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        XCTAssertNil(collector.replies.first?.value)
        assertIsStaleCallbackError(collector.replies.first?.error)
    }

    // MARK: - 5. Controller A→B→A cannot revive evidence, new send admitted

    func testControllerABADuringRelayCannotReviveEvidenceButAdmitsNewSend() async throws {
        let harness = try await makeHarness(name: "SendControllerABA")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.oneShotRequestCount, 1)

        harness.inspection.contextState.profiles.setController(
            replacementController,
            for: harness.profileID
        )
        harness.inspection.contextState.profiles.setController(
            harness.controller,
            for: harness.profileID
        )
        adapter.completeHeldOneShotReplies(value: ["secret": true])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        assertIsStaleCallbackError(collector.replies.first?.error)

        // A fresh callback against the settled A binding must be admitted.
        adapter.completesImmediately = true
        let freshResult = await driveSendMessage(harness: harness)
        XCTAssertNil(freshResult.error)
        XCTAssertEqual((freshResult.value as? [String: Bool])?["pong"], true)
    }

    // MARK: - 6. Extension load generation change invalidates the send

    func testExtensionLoadGenerationChangeDuringRelayInvalidatesSend() async throws {
        let harness = try await makeHarness(name: "SendLoadGeneration")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)

        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.oneShotRequestCount, 1)

        harness.inspection.runtimeAuthorities.loadRevisions.advance()
        adapter.completeHeldOneShotReplies(value: ["secret": true])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        assertIsStaleCallbackError(collector.replies.first?.error)
    }

    // MARK: - 7. Unrelated extension rebind must not invalidate the send

    func testUnrelatedExtensionRebindDuringRelayDoesNotInvalidateSend() async throws {
        let harness = try await makeHarness(name: "SendUnrelatedRebind")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let unrelatedContext = try await makeUnrelatedExtensionContext()

        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.oneShotRequestCount, 1)

        _ = harness.inspection.contextState.profiles.setContext(
            unrelatedContext,
            extensionId: "unrelated-extension",
            profileId: harness.profileID
        )
        adapter.completeHeldOneShotReplies(value: ["pong": true])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        XCTAssertNil(collector.replies.first?.error)
        XCTAssertEqual(
            (collector.replies.first?.value as? [String: Bool])?["pong"],
            true
        )
    }

    // MARK: - 8. Stale-after-await stops the remaining success tail

    func testStaleAfterAwaitStopsRemainingSendTail() async throws {
        let harness = try await makeHarness(name: "SendStaleTail")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.oneShotRequestCount, 1)
        let autofillAfterDispatch = SafariExtensionAutofillFillDiagnostics
            .snapshot().bucketCounts

        rebindSameContext(harness)
        adapter.completeHeldOneShotReplies(value: ["secret": true])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        assertIsStaleCallbackError(collector.replies.first?.error)
        XCTAssertEqual(
            SafariExtensionAutofillFillDiagnostics.snapshot().bucketCounts,
            autofillAfterDispatch,
            "the stale success tail must not record relay-success diagnostics"
        )
    }

    // MARK: - 9. Stale reply never returns the superseded success value

    func testStaleReplyDoesNotReturnSuccess() async throws {
        let harness = try await makeHarness(name: "SendStaleReply")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)

        let collector = await dispatchSend(harness: harness)
        rebindSameContext(harness)
        adapter.completeHeldOneShotReplies(value: ["token": "secret-value"])
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        XCTAssertNil(
            collector.replies.first?.value,
            "a stale callback must never surface the superseded success value"
        )
        assertIsStaleCallbackError(collector.replies.first?.error)
    }

    // MARK: - 10. The send reply settles exactly once

    func testSendReplyIsDeliveredExactlyOnce() async throws {
        let harness = try await makeHarness(name: "SendReplyOnce")
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)

        let collector = await dispatchSend(harness: harness)
        XCTAssertEqual(adapter.heldOneShotReplies.count, 1)
        let heldReply = adapter.heldOneShotReplies[0]

        rebindSameContext(harness)
        // A misbehaving companion boundary settles twice; the callback must
        // still settle exactly once and fail closed.
        heldReply(["first": true], nil)
        heldReply(["second": true], nil)
        await drainMainActorTurns()

        XCTAssertEqual(collector.replies.count, 1)
        assertIsStaleCallbackError(collector.replies.first?.error)
    }

    // MARK: - 19. Manager deallocation fails the callback closed

    func testManagerDeallocationFailsSendClosed() async throws {
        var harness: Harness? = try await makeHarness(name: "SendManagerGone")
        let bridge = try XCTUnwrap(harness?.inspection.controller.delegateBridge)
        let controller = try XCTUnwrap(harness?.controller)
        let context = try XCTUnwrap(harness?.context)
        weak let weakManager = harness?.manager
        harness = nil
        await drainMainActorTurns()
        try XCTSkipUnless(
            weakManager == nil,
            "manager deallocation could not be arranged in this host"
        )

        var replies: [(Any?, (any Error)?)] = []
        bridge.webExtensionController(
            controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: context
        ) { value, error in
            replies.append((value, error))
        }
        await drainMainActorTurns()

        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(replies.first?.0)
        assertIsStaleCallbackError(replies.first?.1)
    }

    // MARK: - 20. Unbound/disabled runtime path stays zero-cost

    func testUnboundRuntimeSendPathStaysZeroCost() async throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: Profile(name: "ZeroCost"),
            testInspectionDidAssemble: inspection.install
        )
        let foreignController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let foreignContext = try await makeUnrelatedExtensionContext()
        let countersBefore = SumiNativeMessagingRuntimeCounters.snapshot()

        var replies: [(Any?, (any Error)?)] = []
        inspection.inspection.controller.delegateBridge.webExtensionController(
            foreignController,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: foreignContext
        ) { value, error in
            replies.append((value, error))
        }
        await drainMainActorTurns()

        XCTAssertEqual(replies.count, 1)
        assertIsStaleCallbackError(replies.first?.1)
        XCTAssertNil(inspection.inspection.nativeMessaging.loadedRelay)
        XCTAssertFalse(
            inspection.inspection.nativeMessaging.hasLoadedWakeOwner
        )
        XCTAssertEqual(
            SumiNativeMessagingRuntimeCounters.snapshot(),
            countersBefore,
            "a rejected callback on an unbound runtime must not touch counters"
        )
        _ = container
    }
}
