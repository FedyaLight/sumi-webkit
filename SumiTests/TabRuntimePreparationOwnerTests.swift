import XCTest

@testable import Sumi

@MainActor
final class TabRuntimePreparationOwnerTests: XCTestCase {
    func testPrepareInvokesRuntimeLifecycleAndBackfillsSettingsFromRuntimeContext() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        var preparedTabIds: [UUID] = []
        let owner = TabRuntimePreparationOwner(
            dependencies: TabRuntimePreparationOwner.Dependencies(
                runtimeContext: {
                    TabManagerRuntimeContext(
                        settings: { settings },
                        webViewLifecycle: TabManagerWebViewLifecycleService(
                            prepareTab: { tab in
                                preparedTabIds.append(tab.id)
                            }
                        )
                    )
                },
                settings: { nil }
            )
        )
        let tab = Tab()

        owner.prepare(tab)

        XCTAssertEqual(preparedTabIds, [tab.id])
        XCTAssertIdentical(tab.sumiSettings, settings)
    }

    func testPrepareKeepsExistingSettings() {
        let existingSettings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let fallbackSettings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let owner = TabRuntimePreparationOwner(
            dependencies: TabRuntimePreparationOwner.Dependencies(
                runtimeContext: {
                    TabManagerRuntimeContext(settings: { fallbackSettings })
                },
                settings: { nil }
            )
        )
        let tab = Tab()
        tab.sumiSettings = existingSettings

        owner.prepare(tab)

        XCTAssertIdentical(tab.sumiSettings, existingSettings)
    }
}
