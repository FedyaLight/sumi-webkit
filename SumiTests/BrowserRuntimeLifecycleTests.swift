import Combine
import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserRuntimeLifecycleTests: XCTestCase {
    func testStartAttachesRuntimeWiringAndBeginsStartupObservations() {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()

        lifecycle.start()

        XCTAssertEqual(harness.permissionObservation.startCount, 1)
        XCTAssertTrue(harness.permissionObservation.isObserving)
        XCTAssertEqual(harness.protectionRestore.beginCount, 1)
        XCTAssertEqual(harness.runtimeWiringCancelCount, 0)
    }

    func testRepeatedStartDoesNotRestartCapabilities() {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()

        lifecycle.start()
        lifecycle.start()

        XCTAssertEqual(harness.permissionObservation.startCount, 1)
        XCTAssertEqual(harness.protectionRestore.beginCount, 1)
    }

    func testInitialDataEventAndRetentionNotificationRouteToLifecycleHandlers() async {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()
        lifecycle.start()

        harness.eventBus.publishInitialDataLoaded()
        harness.notificationCenter.post(name: .sumiBrowsingDataRetentionChanged, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.tabManagerDataLoadedCount, 1)
        XCTAssertEqual(harness.browsingDataRetentionCleanupCount, 1)
    }

    func testShutdownCancelsEverythingStartBegan() async {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()
        lifecycle.start()

        lifecycle.shutdown()

        XCTAssertEqual(harness.runtimeWiringCancelCount, 1)
        XCTAssertEqual(harness.permissionObservation.cancelCount, 1)
        XCTAssertFalse(harness.permissionObservation.isObserving)
        XCTAssertEqual(harness.protectionRestore.cancelCount, 1)

        // Startup event routing is disconnected.
        harness.eventBus.publishInitialDataLoaded()
        harness.notificationCenter.post(name: .sumiBrowsingDataRetentionChanged, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.tabManagerDataLoadedCount, 0)
        XCTAssertEqual(harness.browsingDataRetentionCleanupCount, 0)
    }

    func testRepeatedShutdownIsSafeAndCancelsOnlyOnce() {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()
        lifecycle.start()

        lifecycle.shutdown()
        lifecycle.shutdown()

        XCTAssertEqual(harness.runtimeWiringCancelCount, 1)
        XCTAssertEqual(harness.permissionObservation.cancelCount, 1)
        XCTAssertEqual(harness.protectionRestore.cancelCount, 1)
    }

    func testShutdownSuppressesRetentionCleanupAlreadyQueuedOnMainActor() async {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()
        lifecycle.start()

        harness.notificationCenter.post(name: .sumiBrowsingDataRetentionChanged, object: nil)
        lifecycle.shutdown()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.browsingDataRetentionCleanupCount, 0)
    }

    func testDeinitPerformsShutdownExactlyOnce() {
        let harness = Harness()
        var lifecycle: BrowserRuntimeLifecycle? = harness.makeLifecycle()
        lifecycle?.start()

        lifecycle = nil

        XCTAssertEqual(harness.runtimeWiringCancelCount, 1)
        XCTAssertEqual(harness.permissionObservation.cancelCount, 1)
        XCTAssertEqual(harness.protectionRestore.cancelCount, 1)
    }

    func testShutdownWithoutStartIsSafeAndBlocksLaterStart() {
        let harness = Harness()
        let lifecycle = harness.makeLifecycle()

        lifecycle.shutdown()
        lifecycle.start()

        XCTAssertEqual(harness.permissionObservation.startCount, 0)
        XCTAssertEqual(harness.protectionRestore.beginCount, 0)
    }

    @MainActor
    private final class PermissionObservationFake: BrowserPermissionObservationManaging {
        private(set) var startCount = 0
        private(set) var cancelCount = 0
        private var handler: SumiPermissionEventOwner.EventHandler?

        var isObserving: Bool { handler != nil }

        func startPermissionEventObservation(
            onPermissionEvent: @escaping SumiPermissionEventOwner.EventHandler
        ) {
            startCount += 1
            handler = onPermissionEvent
        }

        func cancelPermissionEventObservation() {
            cancelCount += 1
            handler = nil
        }
    }

    @MainActor
    private final class ProtectionRestoreFake: BrowserStartupProtectionRestoring {
        private(set) var beginCount = 0
        private(set) var cancelCount = 0

        func beginProtectionRestoreForStartupIfNeeded() {
            beginCount += 1
        }

        func cancelProtectionRestoreTask() {
            cancelCount += 1
        }
    }

    @MainActor
    private final class Harness {
        let notificationCenter = NotificationCenter()
        let eventBus = TabStructureEventBus()
        let permissionObservation = PermissionObservationFake()
        let protectionRestore = ProtectionRestoreFake()
        var runtimeWiringCancelCount = 0
        var tabManagerDataLoadedCount = 0
        var browsingDataRetentionCleanupCount = 0

        func makeLifecycle() -> BrowserRuntimeLifecycle {
            BrowserRuntimeLifecycle(
                notificationCenter: notificationCenter,
                notificationQueue: nil,
                tabStructureEventBus: eventBus,
                permissionObservation: permissionObservation,
                onPermissionEvent: { _ in /* Routed by composition; unit fakes only observe start/cancel. */ },
                protectionRestore: protectionRestore,
                runtimeGraphSubscription: AnyCancellable {
                    MainActor.assumeIsolated {
                        self.runtimeWiringCancelCount += 1
                    }
                },
                handleTabManagerDataLoaded: {
                    self.tabManagerDataLoadedCount += 1
                },
                scheduleBrowsingDataRetentionCleanup: {
                    self.browsingDataRetentionCleanupCount += 1
                }
            )
        }
    }
}
