import Combine
import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserManagerInitializationWiringOwnerTests: XCTestCase {
    func testFinishInitializationWiringAttachesRuntimeAndBeginsProtectionRestore() {
        let harness = Harness()
        let owner = harness.makeOwner()

        owner.finishInitializationWiring()

        XCTAssertEqual(harness.attachShellRuntimeCount, 1)
        XCTAssertEqual(harness.attachRuntimeWiringCount, 1)
        XCTAssertEqual(harness.beginProtectionRestoreCount, 1)
        XCTAssertEqual(harness.runtimeWiringCancelCount, 0)
    }

    func testObservedNotificationsRouteToLifecycleHandlers() async {
        let harness = Harness()
        let owner = harness.makeOwner()
        owner.finishInitializationWiring()

        harness.notificationCenter.post(name: .tabManagerDidLoadInitialData, object: nil)
        harness.notificationCenter.post(name: .sumiBrowsingDataRetentionChanged, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.tabManagerDataLoadedCount, 1)
        XCTAssertEqual(harness.browsingDataRetentionCleanupCount, 1)
    }

    func testCancelRemovesObserversAndCancelsRuntimeWiring() async {
        let harness = Harness()
        let owner = harness.makeOwner()
        owner.finishInitializationWiring()

        owner.cancel()
        harness.notificationCenter.post(name: .tabManagerDidLoadInitialData, object: nil)
        harness.notificationCenter.post(name: .sumiBrowsingDataRetentionChanged, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(harness.runtimeWiringCancelCount, 1)
        XCTAssertEqual(harness.tabManagerDataLoadedCount, 0)
        XCTAssertEqual(harness.browsingDataRetentionCleanupCount, 0)
    }

    @MainActor
    private final class Harness {
        let notificationCenter = NotificationCenter()
        var attachShellRuntimeCount = 0
        var attachRuntimeWiringCount = 0
        var runtimeWiringCancelCount = 0
        var tabManagerDataLoadedCount = 0
        var browsingDataRetentionCleanupCount = 0
        var beginProtectionRestoreCount = 0

        func makeOwner() -> BrowserManagerInitializationWiringOwner {
            BrowserManagerInitializationWiringOwner(
                notificationCenter: notificationCenter,
                notificationQueue: nil,
                attachShellRuntime: {
                    self.attachShellRuntimeCount += 1
                },
                attachRuntimeWiring: {
                    self.attachRuntimeWiringCount += 1
                    return AnyCancellable {
                        MainActor.assumeIsolated {
                            self.runtimeWiringCancelCount += 1
                        }
                    }
                },
                handleTabManagerDataLoaded: {
                    self.tabManagerDataLoadedCount += 1
                },
                scheduleBrowsingDataRetentionCleanup: {
                    self.browsingDataRetentionCleanupCount += 1
                },
                beginProtectionRestoreForStartupIfNeeded: {
                    self.beginProtectionRestoreCount += 1
                }
            )
        }
    }
}
