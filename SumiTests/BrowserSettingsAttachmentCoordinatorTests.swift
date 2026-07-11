import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserSettingsAttachmentCoordinatorTests: XCTestCase {
    func testAttachForwardsSettingsToDownloadManager() throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()

        coordinator.attach(harness.settings)

        XCTAssertIdentical(harness.downloadManager.settings, harness.settings)

        coordinator.attach(nil)

        XCTAssertNil(harness.downloadManager.settings)
    }

    func testAttachConfiguresTabSuspensionPolicyFromLiveSettings() throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()
        harness.settings.memoryMode = .maximum

        coordinator.attach(harness.settings)

        XCTAssertEqual(
            harness.tabSuspension.currentPolicyForTesting,
            TabSuspensionPolicy(settings: harness.settings)
        )

        // The policy source tracks later settings changes instead of freezing
        // the values captured at attach time.
        harness.settings.memoryMode = .moderate
        XCTAssertEqual(
            harness.tabSuspension.currentPolicyForTesting,
            TabSuspensionPolicy(settings: harness.settings)
        )
    }

    func testAttachingReplacementSettingsSwitchesPolicySource() throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()
        harness.settings.memoryMode = .maximum
        coordinator.attach(harness.settings)

        let replacement = try harness.makeReplacementSettings()
        replacement.memoryMode = .moderate

        coordinator.attach(replacement)

        XCTAssertEqual(
            harness.tabSuspension.currentPolicyForTesting,
            TabSuspensionPolicy(settings: replacement)
        )
        XCTAssertNotEqual(
            harness.tabSuspension.currentPolicyForTesting,
            TabSuspensionPolicy(settings: harness.settings)
        )

        coordinator.attach(nil)

        XCTAssertEqual(
            harness.tabSuspension.currentPolicyForTesting,
            TabSuspensionPolicy(settings: nil)
        )
    }

    func testAttachSignalsSettingsDependentSubsystems() async throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()

        coordinator.attach(harness.settings)
        await waitUntil {
            harness.backgroundMediaEnergySaverReadCount == 1
                && harness.automaticCleanupRetentionReadCount == 1
        }

        XCTAssertEqual(harness.backgroundMediaEnergySaverReadCount, 1)
        XCTAssertEqual(harness.appliedStartupModes, [.nothing])
        XCTAssertEqual(harness.automaticCleanupRetentionReadCount, 1)
    }

    func testAttachNilStillRunsReconciliationSideEffects() async throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()
        coordinator.attach(harness.settings)
        await waitUntil {
            harness.backgroundMediaEnergySaverReadCount == 1
                && harness.automaticCleanupRetentionReadCount == 1
        }

        coordinator.attach(nil)
        await waitUntil {
            harness.backgroundMediaEnergySaverReadCount == 2
                && harness.automaticCleanupRetentionReadCount == 2
        }

        XCTAssertNil(harness.downloadManager.settings)
        XCTAssertEqual(harness.backgroundMediaEnergySaverReadCount, 2)
        XCTAssertEqual(harness.automaticCleanupRetentionReadCount, 2)
        // Startup policy intentionally applies at most once per process.
        XCTAssertEqual(harness.appliedStartupModes, [.nothing])
    }

    @MainActor
    private final class Harness {
        let downloadManager = DownloadManager()
        let tabSuspension = TabSuspensionController(memoryMonitor: nil)
        let backgroundMedia = SumiBackgroundMediaOptimizationService()
        let startupSessionRestore: BrowserStartupSessionRestoreOwner
        let settings: SumiSettingsService
        private let startupWindowState = BrowserWindowState()
        private var defaultsSuiteNames: [String] = []
        private(set) var backgroundMediaEnergySaverReadCount = 0
        private(set) var appliedStartupModes: [SumiStartupMode] = []
        private(set) var automaticCleanupRetentionReadCount = 0

        init() throws {
            let defaults = try Self.makeDefaults(
                suiteName: "BrowserSettingsAttachmentCoordinatorTests-\(UUID().uuidString)",
                register: &defaultsSuiteNames
            )
            self.settings = SumiSettingsService(userDefaults: defaults)
            self.startupSessionRestore = BrowserStartupSessionRestoreOwner(
                lastSessionWindowsStore: LastSessionWindowsStore(userDefaults: defaults)
            )
            backgroundMedia.attach(
                runtime: SumiBackgroundMediaOptimizationRuntime(
                    liveWebViewEntries: { _ in [] },
                    energySaverActive: { [weak self] in
                        self?.backgroundMediaEnergySaverReadCount += 1
                        return false
                    },
                    allKnownTabs: { [] },
                    visibleTabIDsByWindow: { [:] }
                )
            )
        }

        deinit {
            for suiteName in defaultsSuiteNames {
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
            }
        }

        func makeCoordinator() -> BrowserSettingsAttachmentCoordinator {
            let startupSessionRestore = startupSessionRestore
            let startupWindowState = startupWindowState
            return BrowserSettingsAttachmentCoordinator(
                downloadManager: downloadManager,
                tabSuspension: tabSuspension,
                backgroundMedia: backgroundMedia,
                reconcileStartupSession: { [weak self] in
                    startupSessionRestore.reconcileIfReady(
                        hasLoadedInitialTabData: { true },
                        startupMode: { .nothing },
                        startupWindow: { [startupWindowState] in startupWindowState },
                        applyStartupPolicy: { mode in
                            self?.appliedStartupModes.append(mode)
                        }
                    )
                },
                automaticDataCleanup: BrowserAutomaticDataCleanupOwner(
                    permissionRuntime: { nil },
                    dataServices: { nil },
                    retentionPeriod: { [weak self] in
                        self?.automaticCleanupRetentionReadCount += 1
                        return nil
                    },
                    historyManager: { nil },
                    profiles: { [] },
                    currentProfileId: { nil }
                )
            )
        }

        func makeReplacementSettings() throws -> SumiSettingsService {
            let defaults = try Self.makeDefaults(
                suiteName: "BrowserSettingsAttachmentCoordinatorTests-replacement-\(UUID().uuidString)",
                register: &defaultsSuiteNames
            )
            return SumiSettingsService(userDefaults: defaults)
        }

        private static func makeDefaults(
            suiteName: String,
            register: inout [String]
        ) throws -> UserDefaults {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            register.append(suiteName)
            return defaults
        }
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
}
