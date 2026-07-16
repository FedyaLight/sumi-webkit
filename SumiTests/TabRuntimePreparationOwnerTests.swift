import XCTest

@testable import Sumi

@MainActor
final class TabRuntimePreparationOwnerTests: XCTestCase {
    func testPrepareInvokesRuntimeLifecycleAndBackfillsSettingsFromRuntimeContext() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        var preparedTabIds: [UUID] = []
        let connection = TabRuntimePortConnection()
        connection.attach(TestRuntimePorts.make(
            settings: { settings },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { tab in
                    preparedTabIds.append(tab.id)
                }
            )
        ))
        let owner = TabRuntimePreparationOwner(
            runtimeConnection: connection
        )
        let tab = Tab()

        owner.prepare(tab)

        XCTAssertEqual(preparedTabIds, [tab.id])
        XCTAssertIdentical(tab.sumiSettings, settings)
    }

    func testPrepareKeepsExistingSettings() {
        let existingSettings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let fallbackSettings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let connection = TabRuntimePortConnection()
        connection.attach(TestRuntimePorts.make(
            settings: { fallbackSettings }
        ))
        let owner = TabRuntimePreparationOwner(
            runtimeConnection: connection
        )
        let tab = Tab()
        tab.sumiSettings = existingSettings

        owner.prepare(tab)

        XCTAssertIdentical(tab.sumiSettings, existingSettings)
    }

    func testPrepareDoesNotPublishSettingsAfterAttachmentIsSuperseded() {
        let firstSettings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let secondSettings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let connection = TabRuntimePortConnection()
        let second = TestRuntimePorts.make(settings: { secondSettings })
        let first = TestRuntimePorts.make(
            settings: { firstSettings },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in
                    connection.detach()
                    connection.attach(second)
                }
            )
        )
        connection.attach(first)
        let owner = TabRuntimePreparationOwner(runtimeConnection: connection)
        let tab = Tab()

        XCTAssertEqual(owner.prepare(tab), .superseded)

        XCTAssertNil(tab.sumiSettings)
        XCTAssertIdentical(connection.current?.settings, secondSettings)
    }
}
