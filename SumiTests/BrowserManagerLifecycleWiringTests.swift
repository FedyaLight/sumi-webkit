import Foundation
@testable import Sumi
import SwiftData
import XCTest

/// Production-shaped integration coverage: exercises the runtime lifecycle and
/// settings-attachment workflows through a real `BrowserManager`, asserting
/// observable effects on the live subsystems instead of injected counters.
@MainActor
final class BrowserManagerLifecycleWiringTests: XCTestCase {
    func testInitializationStartsRuntimeLifecycleAgainstLiveSubsystems() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )

        XCTAssertTrue(browserManager.permissionRuntime.isObservingPermissionEvents)
        // In tests the protection restore short-circuits synchronously, so a
        // finished restore proves the lifecycle began it during init.
        XCTAssertTrue(browserManager.startupProtectionRuntime.hasFinishedProtectionRestore)
        XCTAssertNotNil(browserManager.tabManager.runtimePorts)
    }

    func testSettingsAttachmentReconfiguresLiveSubsystemsThroughDidSet() async throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        var backgroundMediaAvailabilityReads = 0
        browserManager.backgroundMediaOptimizationService.attach(
            runtime: SumiBackgroundMediaOptimizationRuntime(
                webViewRuntimeAvailable: {
                    backgroundMediaAvailabilityReads += 1
                    return false
                },
                liveWebViewEntries: { _ in [] },
                energySaverActive: { false },
                allKnownTabs: { [] },
                visibleTabIDsByWindow: { [:] }
            )
        )
        // Runtime wiring schedules an initial window-registry reconcile before
        // this test replaces the runtime. Drain that known request so each
        // settings assignment below has an isolated observable increment.
        await waitUntil { backgroundMediaAvailabilityReads > 0 }
        let backgroundMediaBaseline = backgroundMediaAvailabilityReads

        let settings = try makeSettings(suiteName: "primary")
        settings.memoryMode = .maximum

        browserManager.sumiSettings = settings

        XCTAssertIdentical(browserManager.downloadManager.settings, settings)
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: settings)
        )

        // Later settings mutations flow through the live policy source.
        settings.memoryMode = .moderate
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: settings)
        )

        // Background-media reconciliation was genuinely scheduled by the attach.
        await waitUntil {
            backgroundMediaAvailabilityReads == backgroundMediaBaseline + 1
        }
        XCTAssertEqual(backgroundMediaAvailabilityReads, backgroundMediaBaseline + 1)

        // Replacing the settings service switches every consumer to the new one.
        let replacement = try makeSettings(suiteName: "replacement")
        replacement.memoryMode = .maximum

        browserManager.sumiSettings = replacement

        XCTAssertIdentical(browserManager.downloadManager.settings, replacement)
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: replacement)
        )
        XCTAssertNotEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: settings)
        )

        await waitUntil {
            backgroundMediaAvailabilityReads == backgroundMediaBaseline + 2
        }

        // Detaching keeps the nil-attach workflow intact.
        browserManager.sumiSettings = nil

        XCTAssertNil(browserManager.downloadManager.settings)
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: nil)
        )
        await waitUntil {
            backgroundMediaAvailabilityReads == backgroundMediaBaseline + 3
        }
        XCTAssertEqual(backgroundMediaAvailabilityReads, backgroundMediaBaseline + 3)
    }

    func testInitialDataLoadedEventAppliesStartupPolicyThroughLiveWiring() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let settings = try makeSettings(suiteName: "startup")
        settings.startupMode = .nothing
        browserManager.sumiSettings = settings
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore(
            userDefaults: try makeDefaults(suiteName: "startup-last-session")
        )

        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        let space = browserManager.tabManager.spaceStateOwner.currentSpace
            ?? browserManager.tabManager.spaceServices.catalog.createSpace(name: "Startup Wiring")
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.isShowingEmptyState = false
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        XCTAssertFalse(windowState.isShowingEmptyState)

        // Publishing initial-data-loaded on the real event bus must reach the
        // startup-session owner through the live lifecycle subscription and
        // apply the configured "nothing" startup policy.
        browserManager.tabManager.startupRestoreLifecycle.markLoadFinished()

        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false, clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Condition was not satisfied before \(timeout)")
    }

    private var defaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in defaultsSuiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaultsSuiteNames = []
        super.tearDown()
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let fullSuiteName = "BrowserManagerLifecycleWiringTests-\(suiteName)-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: fullSuiteName))
        defaultsSuiteNames.append(fullSuiteName)
        return defaults
    }

    private func makeSettings(suiteName: String) throws -> SumiSettingsService {
        SumiSettingsService(userDefaults: try makeDefaults(suiteName: suiteName))
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
