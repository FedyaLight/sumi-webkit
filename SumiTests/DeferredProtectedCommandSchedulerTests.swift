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

        XCTAssertEqual(fixture.admission.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.flush"
        ), .scheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
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
        XCTAssertTrue(fixture.admission.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.duplicate-flush"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
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
        XCTAssertTrue(fixture.admission.schedule(
            .assignSpaceProfile(intent: intent),
            for: webView,
            reason: "test.prune"
        ).wasScheduled)

        fixture.spaceIntents.current = nil
        fixture.admission.pruneInvalidCommands(reason: "test.invalidated")
        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
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
        XCTAssertTrue(fixture.admission.schedule(
            .assignSpaceProfile(intent: intent),
            for: webView,
            reason: "test.race"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
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
        XCTAssertTrue(fixture.admission.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.reprotected"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(firstLease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
        let secondLease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 0)
        XCTAssertTrue(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))

        _ = fixture.mediaProtection.finishVisualHandoffProtection(secondLease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()
        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
    }

    func testGuaranteedCommandRetriesUntilEffectSucceeds() async {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let fixture = SchedulerFixture(delayedActions: delayedActions.scheduler)
        fixture.effects.succeedContainerRemovalAfterAttempt = 3
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.admission.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.retry"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
        XCTAssertEqual(delayedActions.scheduledDelays, [0.025])

        delayedActions.runNext()
        await drainSchedulerTasks()
        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 2)
        XCTAssertEqual(delayedActions.scheduledDelays, [0.05])

        delayedActions.runNext()
        await drainSchedulerTasks()

        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 3)
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        XCTAssertFalse(fixture.mediaProtection.hasDeferredProtectedCommands(
            for: ObjectIdentifier(webView)
        ))
    }

    func testTerminalResetCancelsPendingRetryTask() async {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let fixture = SchedulerFixture(delayedActions: delayedActions.scheduler)
        fixture.effects.succeedContainerRemovalAfterAttempt = .max
        let webView = WKWebView()
        let lease = fixture.mediaProtection.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(fixture.admission.schedule(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "test.reset"
        ).wasScheduled)

        _ = fixture.mediaProtection.finishVisualHandoffProtection(lease)
        fixture.processor.flushCommands(for: ObjectIdentifier(webView))
        await drainSchedulerTasks()
        XCTAssertEqual(fixture.effects.containerRemovalAttempts, 1)
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        fixture.processor.resetForTerminalShutdown()
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()
        await drainSchedulerTasks()

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
    let admission: DeferredProtectedCommandAdmissionService
    let processor: DeferredProtectedCommandProcessor

    init(delayedActions: MainActorDelayedActionScheduler = .live) {
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
        let retryLedger = DeferredProtectedCommandRetryLedger()
        admission = DeferredProtectedCommandAdmissionService(
            mediaProtection: mediaProtection,
            webViews: webViews,
            authority: authority,
            retryLedger: retryLedger,
            finishCleanupSuppression: { _ in }
        )
        processor = DeferredProtectedCommandProcessor(
            mediaProtection: mediaProtection,
            webViews: webViews,
            authority: authority,
            executor: DeferredWebViewCommandExecutor(
                cleanup: cleanup,
                windowMaintenance: windowMaintenance,
                configuration: configuration
            ),
            retryLedger: retryLedger,
            delayedActions: delayedActions,
            finishCleanupSuppression: { _ in }
        )
    }
}

private func drainSchedulerTasks() async {
    await Task.yield()
    await Task.yield()
}
