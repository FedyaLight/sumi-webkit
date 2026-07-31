import Foundation
@testable import Sumi
import XCTest

/// Production-shaped integration coverage: exercises the runtime lifecycle and
/// settings-attachment workflows through a real `BrowserManager`, asserting
/// observable effects on the live subsystems instead of injected counters.
@MainActor
final class BrowserManagerLifecycleWiringTests: XCTestCase {
    func testInitializationAttachesRuntimeGraphButDefersLifecycleUntilRecoveryGate() throws {
        let moduleRegistry = SumiModuleRegistry.unavailable()
        SumiProtectionSettings(userDefaults: moduleRegistry.userDefaults)
            .setAppliedLevel(.protection)
        let browserManager = BrowserManager(
            moduleRegistry: moduleRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let startupProbe = Tab(
            url: URL(string: "https://startup-protection.example")!,
            loadsCachedFaviconOnInit: false
        )

        XCTAssertFalse(browserManager.permissionRuntime.isObservingPermissionEvents)
        XCTAssertFalse(
            browserManager.startupProtectionRuntime
                .canMaterializeWebViewDuringStartup(startupProbe)
        )
        XCTAssertNotNil(browserManager.runtimePortConnection.current)

        browserManager.startRuntimeAfterStartupRecovery()

        XCTAssertTrue(browserManager.permissionRuntime.isObservingPermissionEvents)
        XCTAssertTrue(
            browserManager.startupProtectionRuntime
                .canMaterializeWebViewDuringStartup(startupProbe)
        )
    }

    func testSettingsAttachmentReconfiguresLiveSubsystemsThroughDidSet() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        browserManager.startRuntimeAfterStartupRecovery()

        let settings = try makeSettings(suiteName: "primary")
        settings.memoryMode = .maximum

        browserManager.sumiSettings = settings

        XCTAssertIdentical(browserManager.downloadManager.settings, settings)
        XCTAssertIdentical(browserManager.runtimePortConnection.current?.settings, settings)
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

        // Replacing the settings service switches every consumer to the new one.
        let replacement = try makeSettings(suiteName: "replacement")
        replacement.memoryMode = .maximum

        browserManager.sumiSettings = replacement

        XCTAssertIdentical(browserManager.downloadManager.settings, replacement)
        XCTAssertIdentical(browserManager.runtimePortConnection.current?.settings, replacement)
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: replacement)
        )
        XCTAssertNotEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: settings)
        )

        // Detaching keeps the nil-attach workflow intact.
        browserManager.sumiSettings = nil

        XCTAssertNil(browserManager.downloadManager.settings)
        XCTAssertNil(browserManager.runtimePortConnection.current?.settings)
        XCTAssertEqual(
            browserManager.tabSuspensionController.currentPolicyForTesting,
            TabSuspensionPolicy(settings: nil)
        )
    }

    func testInitialDataLoadedEventAppliesStartupPolicyThroughLiveWiring() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        browserManager.startRuntimeAfterStartupRecovery()
        let settings = try makeSettings(suiteName: "startup")
        settings.startupMode = .nothing
        browserManager.sumiSettings = settings
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore()

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Startup Wiring"
            )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.isShowingEmptyState = false
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        XCTAssertFalse(windowState.isShowingEmptyState)

        // Publishing initial-data-loaded on the real event bus must reach the
        // startup-session owner through the live lifecycle subscription and
        // apply the configured "nothing" startup policy.
        browserManager.startupRestoreLifecycle.markLoadFinished()

        XCTAssertTrue(windowState.isShowingEmptyState)
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

    private func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}
