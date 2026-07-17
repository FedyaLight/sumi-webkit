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
                && harness.automaticCleanupScheduleCount == 1
        }

        XCTAssertEqual(harness.backgroundMediaEnergySaverReadCount, 1)
        XCTAssertEqual(harness.automaticCleanupScheduleCount, 1)
    }

    func testAttachNilStillRunsReconciliationSideEffects() async throws {
        let harness = try Harness()
        let coordinator = harness.makeCoordinator()
        coordinator.attach(harness.settings)
        await waitUntil {
            harness.backgroundMediaEnergySaverReadCount == 1
                && harness.automaticCleanupScheduleCount == 1
        }

        coordinator.attach(nil)
        await waitUntil {
            harness.backgroundMediaEnergySaverReadCount == 2
                && harness.automaticCleanupScheduleCount == 1
        }

        XCTAssertNil(harness.downloadManager.settings)
        XCTAssertEqual(harness.backgroundMediaEnergySaverReadCount, 2)
        XCTAssertEqual(harness.automaticCleanupScheduleCount, 1)
    }

    @MainActor
    private final class Harness {
        let browserManager: BrowserManager
        let settings: SumiSettingsService
        private let automaticCleanup = RecordingBrowsingDataCleanupScheduler()
        private var defaultsSuiteNames: [String] = []
        private(set) var backgroundMediaEnergySaverReadCount = 0

        var downloadManager: DownloadManager { browserManager.downloadManager }
        var tabSuspension: TabSuspensionController {
            browserManager.tabSuspensionController
        }
        var automaticCleanupScheduleCount: Int {
            automaticCleanup.requests.count
        }

        init() throws {
            let defaults = try Self.makeDefaults(
                suiteName: "BrowserSettingsAttachmentCoordinatorTests-\(UUID().uuidString)",
                register: &defaultsSuiteNames
            )
            self.settings = SumiSettingsService(userDefaults: defaults)
            let unavailable = BrowserManagerDataServices.unavailable()
            self.browserManager = BrowserManager(
                dataServices: BrowserManagerDataServices(
                    websiteDataCleanupService: unavailable.websiteDataCleanupService,
                    browsingDataCleanupService: unavailable.browsingDataCleanupService,
                    automaticBrowsingDataCleanupService: automaticCleanup,
                    siteDataPolicyStore: unavailable.siteDataPolicyStore,
                    siteDataPolicyEnforcementService: unavailable.siteDataPolicyEnforcementService,
                    faviconService: unavailable.faviconService,
                    faviconCapabilities: unavailable.faviconCapabilities,
                    visitedLinkStore: unavailable.visitedLinkStore,
                    historyFaviconCleaner: unavailable.historyFaviconCleaner,
                    historyVisitedLinkStore: unavailable.historyVisitedLinkStore,
                    privacyService: unavailable.privacyService,
                    profileWebsiteDataMutationService: unavailable.profileWebsiteDataMutationService
                )
            )
            browserManager.backgroundMediaOptimizationService.attach(
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
            browserManager.settingsAttachment
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

    @MainActor
    private final class RecordingBrowsingDataCleanupScheduler:
        BrowsingDataCleanupScheduling {
        private(set) var requests: [SumiBrowsingDataCleanupScheduleRequest] = []

        func attachDestructiveCleanupPreparer(
            _: (any SumiDestructiveBrowsingDataCleanupPreparing)?
        ) {}

        func scheduleIfNeeded(_ request: SumiBrowsingDataCleanupScheduleRequest) {
            requests.append(request)
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
