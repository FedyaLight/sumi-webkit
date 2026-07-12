import WebKit
import XCTest

@testable import Sumi

/// Integration tests for the callback-admitted native-messaging background
/// wake: the wake key derives only from captured evidence, a stale scheduled
/// wake never loads a superseded context, and a stale scheduled entry never
/// displaces or outlives the newer admissible wake for the same logical key.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingWakeCallbackAdmissionTests:
    ExtensionNativeMessagingAdmissionTestCase {
    /// Arms the debug wake hook and returns a recorder of every background
    /// load the callback path performs from this point on. Any wake state
    /// left by runtime activation is drained and cleared first, so the
    /// recorder observes exactly the callback-admitted loads.
    private func armWakeRecorder(_ harness: Harness) async -> WakeRecorder {
        await drainScheduledRuntimeTasks(harness)
        harness.manager.backgroundRuntimeStateOwner.removeAll()
        let recorder = WakeRecorder()
        harness.manager.testHooks.backgroundContentWake = { wakeKey, _ in
            recorder.loadedWakeKeys.append(wakeKey)
        }
        return recorder
    }

    private func expectedWakeKey(_ harness: Harness) -> String {
        ExtensionRuntimeResidencyState.scopedKey(
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )
    }

    // MARK: - Admitted baseline: the wake key comes from captured identity

    func testAdmittedSendWakesBackgroundUnderEvidenceScopedKey() async throws {
        let harness = try await makeHarness(
            name: "WakeAdmitted",
            withBackgroundContent: true
        )
        let recorder = await armWakeRecorder(harness)

        _ = await driveSendMessage(harness: harness)
        await drainScheduledRuntimeTasks(harness)

        XCTAssertEqual(recorder.loadedWakeKeys, [expectedWakeKey(harness)])
    }

    // MARK: - 3. Context replacement before the scheduled task starts

    func testContextReplacementBeforeScheduledTaskPreventsWakeAndRelay() async throws {
        let harness = try await makeHarness(
            name: "WakePreTaskReplacement",
            withBackgroundContent: true
        )
        let adapter = HoldableProtocolAdapter(
            supportedHosts: [Self.fixtureHostBundleID]
        )
        try installFakeCompanionBoundary(harness: harness, adapter: adapter)
        let recorder = await armWakeRecorder(harness)
        let replacement = WKWebExtensionContext(
            for: harness.context.webExtension
        )

        let collector = SendReplyCollector()
        harness.manager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: harness.context
        ) { value, error in
            collector.record(value, error)
        }
        // The wake and relay tasks are scheduled but have not started yet;
        // replacing the context now must prevent both effects.
        _ = harness.manager.profileRuntime.setContext(
            replacement,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )
        await drainScheduledRuntimeTasks(harness)

        XCTAssertEqual(recorder.loadedWakeKeys, [])
        XCTAssertEqual(adapter.oneShotRequestCount, 0)
        XCTAssertEqual(collector.replies.count, 1)
        assertIsStaleCallbackError(collector.replies.first?.error)
    }

    // MARK: - 17. A stale background task never loads the context

    func testStaleBackgroundWakeTaskDoesNotLoadContext() async throws {
        let harness = try await makeHarness(
            name: "WakeStaleTask",
            withBackgroundContent: true
        )
        let recorder = await armWakeRecorder(harness)

        let collector = await dispatchSendWithoutRelayBoundary(harness: harness) {
            // Same-object rebind between scheduling and the wake task run.
            self.rebindSameContext(harness)
        }
        await drainScheduledRuntimeTasks(harness)

        XCTAssertEqual(
            recorder.loadedWakeKeys,
            [],
            "a stale scheduled wake must not load background content"
        )
        XCTAssertEqual(collector.replies.count, 1)
    }

    // MARK: - 18. A stale scheduled wake never displaces the newer wake

    func testStaleScheduledWakeDoesNotRemoveNewerWakeForSameKey() async throws {
        let harness = try await makeHarness(
            name: "WakeStaleVsNewer",
            withBackgroundContent: true
        )
        let recorder = await armWakeRecorder(harness)

        // Both callbacks dispatch in the same main-actor turn: the first
        // schedules a wake whose evidence immediately goes stale, and the
        // second (admissible) callback for the same logical key must
        // supersede that stale scheduled entry — while the stale task in
        // turn must not remove the newer wake when it unwinds.
        let firstCollector = SendReplyCollector()
        let secondCollector = SendReplyCollector()
        harness.manager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: harness.context
        ) { value, error in
            firstCollector.record(value, error)
        }
        rebindSameContext(harness)
        harness.manager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: harness.context
        ) { value, error in
            secondCollector.record(value, error)
        }
        await drainScheduledRuntimeTasks(harness)

        XCTAssertEqual(recorder.loadedWakeKeys, [expectedWakeKey(harness)])
        XCTAssertEqual(firstCollector.replies.count, 1)
        XCTAssertEqual(secondCollector.replies.count, 1)
    }

    /// Dispatches sendMessage through the real bridge without the fake
    /// companion boundary (the real relay settles the reply via policy),
    /// running `afterDispatch` in the same main-actor turn as the dispatch.
    private func dispatchSendWithoutRelayBoundary(
        harness: Harness,
        afterDispatch: (@MainActor () -> Void)? = nil
    ) async -> SendReplyCollector {
        let collector = SendReplyCollector()
        harness.manager.controllerDelegateBridge.webExtensionController(
            harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: Self.fixtureHostBundleID,
            for: harness.context
        ) { value, error in
            collector.record(value, error)
        }
        afterDispatch?()
        await drainMainActorTurns()
        return collector
    }
}

@MainActor
private final class WakeRecorder {
    var loadedWakeKeys: [String] = []
}
