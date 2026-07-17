import XCTest

@testable import Sumi

@MainActor
final class BrowserRuntimeLifecycleTests: XCTestCase {
    func testRepeatedStartKeepsExactRuntimeAttachment() {
        let browser = BrowserManager()
        let connection = browser.runtimePortConnection
        let attachment = connection.captureLease()

        browser.startRuntimeAfterStartupRecovery()
        browser.startRuntimeAfterStartupRecovery()

        XCTAssertNotNil(connection.current)
        XCTAssertTrue(
            connection.sameAttachment(
                attachment,
                connection.captureLease()
            )
        )
    }

    func testRepeatedStartKeepsOneWebViewCommandDeliverySubscription() {
        let browser = BrowserManager()
        let window = BrowserWindowState()
        browser.windowRegistry.register(window)

        browser.startRuntimeAfterStartupRecovery()
        browser.startRuntimeAfterStartupRecovery()
        browser.webViewWindowCommands.refreshCompositor(in: window.id)

        XCTAssertEqual(
            window.compositorInvalidation.compositorVersion,
            1
        )
    }

    func testShutdownDetachesRuntimeAndCancelsWebViewCommandDelivery() {
        let registry = WindowRegistry()
        var browser: BrowserManager? = BrowserManager(windowRegistry: registry)
        let window = BrowserWindowState()
        registry.register(window)
        browser?.startRuntimeAfterStartupRecovery()
        let connection = browser?.runtimePortConnection
        let commands = browser?.webViewWindowCommands
        commands?.refreshCompositor(in: window.id)

        browser = nil
        commands?.refreshCompositor(in: window.id)

        XCTAssertNil(connection?.current)
        XCTAssertEqual(
            window.compositorInvalidation.compositorVersion,
            1
        )
    }

    func testRepeatedShutdownIsIdempotent() {
        let browser = BrowserManager()

        browser.tabRuntimeLifecycle.shutdown()
        browser.tabRuntimeLifecycle.shutdown()

        XCTAssertNil(browser.runtimePortConnection.current)
    }

    func testShutdownDetachesBackgroundMediaOptimization() async {
        var browser: BrowserManager? = BrowserManager()
        var energySaverReadCount = 0
        let backgroundMedia = browser?.backgroundMediaOptimizationService
        backgroundMedia?.attach(
            runtime: SumiBackgroundMediaOptimizationRuntime(
                liveWebViewEntries: { _ in [] },
                energySaverActive: {
                    energySaverReadCount += 1
                    return false
                },
                allKnownTabs: { [] },
                visibleTabIDsByWindow: { [:] }
            )
        )
        browser?.startRuntimeAfterStartupRecovery()

        browser = nil
        backgroundMedia?.scheduleReconcile(
            reason: "after-shutdown"
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(energySaverReadCount, 0)
    }
}
