import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class DeferredProtectedCommandSchedulerTests: XCTestCase {
    func testFlushAfterProtectionReleaseExecutesCommandOnce() async {
        let fixture = SchedulerFixture()
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)

        XCTAssertEqual(fixture.scheduler.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.flush"
        ), .scheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
        XCTAssertFalse(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
    }

    func testDuplicateFlushRequestsDoNotExecuteCommandTwice() async {
        let fixture = SchedulerFixture()
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.duplicate-flush"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
    }

    func testInvalidCommandIsPrunedWithoutExecutingEffects() async {
        let fixture = SchedulerFixture()
        let webView = WKWebView()
        let intent = DeferredWebViewSpaceProfileAssignmentIntent(
            revision: 1,
            spaceID: UUID(),
            expectedProfileID: nil,
            desiredProfileID: UUID(),
            tabIntents: []
        )
        fixture.spaceIntents.current = intent
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .assignSpaceProfile(intent: intent),
            for: webView,
            reason: "test.prune"
        ).wasScheduled)

        fixture.spaceIntents.current = nil
        fixture.scheduler.pruneInvalidCommands(reason: "test.invalidated")
        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.spaceProfileAttempts, 0)
        XCTAssertFalse(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
    }

    func testInvalidationBetweenFlushRequestAndTaskExecutionHasNoEffects() async {
        let fixture = SchedulerFixture()
        let webView = WKWebView()
        let intent = DeferredWebViewSpaceProfileAssignmentIntent(
            revision: 1,
            spaceID: UUID(),
            expectedProfileID: nil,
            desiredProfileID: UUID(),
            tabIntents: []
        )
        fixture.spaceIntents.current = intent
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .assignSpaceProfile(intent: intent),
            for: webView,
            reason: "test.race"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        fixture.spaceIntents.current = nil
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.spaceProfileAttempts, 0)
        XCTAssertFalse(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
    }

    func testReprotectionBeforeFlushKeepsCommandQueued() async {
        let fixture = SchedulerFixture()
        let webView = WKWebView()
        let firstLease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.reprotected"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(firstLease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        let secondLease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 0)
        XCTAssertTrue(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))

        _ = fixture.mediaProtection.finishVisualHandoffProtection(secondLease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()
        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
    }

    func testGuaranteedCommandRetriesUntilEffectSucceeds() async {
        let fixture = SchedulerFixture()
        fixture.effects.succeedContainerRemovalAfterAttempt = 3
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.retry"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        for _ in 0..<100 where fixture.effects.containerRemovalAttempts < 3 {
            await waitForScheduler(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 3)
        XCTAssertFalse(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
    }

    func testTerminalResetCancelsPendingRetryTask() async {
        let fixture = SchedulerFixture()
        fixture.effects.succeedContainerRemovalAfterAttempt = .max
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.scheduler.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.reset"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.scheduler.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()
        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)

        fixture.scheduler.resetForTerminalShutdown()
        await waitForScheduler(nanoseconds: 80_000_000)

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
    }
}

@MainActor
private final class SchedulerEffects {
    var containerRemovalAttempts = 0
    var succeedContainerRemovalAfterAttempt = 1
    var spaceProfileAttempts = 0

    func removeFromContainers(_: WKWebView) -> Bool {
        containerRemovalAttempts += 1
        return containerRemovalAttempts >= succeedContainerRemovalAfterAttempt
    }
}

@MainActor
private final class SchedulerTabResolver: DeferredWebViewCommandTabResolving {
    func resolveRuntimeTab(with _: UUID) -> Tab? { nil }
    func resolveCollectionTab(with _: UUID) -> Tab? { nil }
    func resolveTabForCleanup(with _: UUID) -> Tab? { nil }
}

@MainActor
private final class SchedulerWindowQuery: DeferredWebViewCommandWindowQuerying {
    func containsWindow(with _: UUID) -> Bool { false }
}

@MainActor
private final class SchedulerSpaceIntentValidator:
    DeferredWebViewSpaceProfileIntentValidating {
    var current: DeferredWebViewSpaceProfileAssignmentIntent?

    func isCurrent(_ intent: DeferredWebViewSpaceProfileAssignmentIntent) -> Bool {
        intent == current
    }
}

@MainActor
private final class SchedulerFixture {
    let sessions = WebViewSessionRepository()
    let mediaProtection = WebViewMediaProtectionOwner()
    let effects = SchedulerEffects()
    let spaceIntents = SchedulerSpaceIntentValidator()
    let scheduler: DeferredProtectedCommandScheduler

    init() {
        let webViews = WebViewRuntimeWebViewResolver(
            sessions: sessions,
            mediaProtection: mediaProtection
        )
        let authority = DeferredWebViewCommandAuthority(
            webViews: webViews,
            webViewSessions: sessions,
            tabs: SchedulerTabResolver(),
            tabScopedCleanupValidation: WebViewTabScopedCleanupValidationOwner(),
            visibleRuntime: VisibleWebViewRuntimeOwner(),
            windows: SchedulerWindowQuery(),
            spaceProfileIntents: spaceIntents
        )
        let cleanup = DeferredWebViewCleanupExecutor(
            sessions: sessions,
            closeWebView: { _ in false },
            removeFromContainers: effects.removeFromContainers,
            cleanupTrackedWebView: { _, _, _ in false },
            shutdownOwnerlessWebView: { _, _ in },
            finishRetirementIfDrained: { _ in }
        )
        let windowMaintenance = DeferredWebViewWindowMaintenanceExecutor(
            cleanupWindow: { _ in false },
            cleanupAllWebViews: { false },
            evictHiddenWebViews: { _, _ in false },
            visibleTabIDs: { _ in [] }
        )
        let configuration = DeferredWebViewConfigurationExecutor(
            rebuild: { _, _, _ in .failed },
            assignProfile: { _, _, _ in false },
            assignSpaceProfile: { [effects] _ in
                effects.spaceProfileAttempts += 1
                return true
            }
        )
        scheduler = DeferredProtectedCommandScheduler(
            mediaProtection: mediaProtection,
            webViews: webViews,
            authority: authority,
            executor: DeferredWebViewCommandExecutor(
                cleanup: cleanup,
                windowMaintenance: windowMaintenance,
                configuration: configuration
            ),
            finishCleanupSuppression: { _ in }
        )
    }
}

private func drainSchedulerTasks() async {
    await Task.yield()
    await Task.yield()
}

private func waitForScheduler(nanoseconds: UInt64) async {
    do {
        try await Task.sleep(nanoseconds: nanoseconds)
    } catch {
        // Cancellation is the behavior under test for terminal reset.
    }
}
