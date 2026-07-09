import Combine
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiBoostsModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDisabledModuleAccessorsDoNotConstructStore() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = BoostRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)
        let url = try XCTUnwrap(URL(string: "https://example.test/page"))

        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(module.canBoost(url: url))
        XCTAssertTrue(module.changedBoosts(for: url, profileId: UUID()).isEmpty)
        XCTAssertNil(module.activeBoost(for: url, profileId: UUID()))
        XCTAssertNil(module.activeBoostId(for: url, profileId: UUID()))
        XCTAssertEqual(module.sizeOverride(for: url, profileId: UUID()), 1)
        XCTAssertTrue(
            module.normalTabUserScripts(
                for: url,
                profileId: UUID(),
                isEphemeral: false
            ).isEmpty
        )

        let tab = Tab(url: url)
        XCTAssertThrowsError(try module.createBoost(tab: tab, profile: nil)) { error in
            XCTAssertEqual(error as? SumiBoostStoreError, .moduleDisabled)
        }
        XCTAssertThrowsError(try module.importBoost(from: Data(), tab: tab, profile: nil)) { error in
            XCTAssertEqual(error as? SumiBoostStoreError, .moduleDisabled)
        }

        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testSetEnabledPersistsWithoutConstructingStore() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = BoostRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)

        module.setEnabled(true)

        XCTAssertTrue(registry.isEnabled(.boosts))
        XCTAssertTrue(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(probe.storeCount, 0)

        module.setEnabled(false)

        XCTAssertFalse(registry.isEnabled(.boosts))
        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(probe.storeCount, 0)
    }

    func testEnabledModuleConstructsStoreLazilyOnce() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.boosts)
        let probe = BoostRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)
        let url = try XCTUnwrap(URL(string: "https://example.test/page"))

        XCTAssertTrue(module.canBoost(url: url))
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(probe.storeCount, 0)

        XCTAssertTrue(module.changedBoosts(for: url, profileId: UUID()).isEmpty)
        XCTAssertNil(module.activeBoost(for: url, profileId: UUID()))

        XCTAssertTrue(module.hasLoadedRuntime)
        XCTAssertEqual(probe.storeCount, 1)
    }

    func testDisabledModuleContributesNoScriptsAndNoZoomMultiplier() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = BoostRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)
        let url = try XCTUnwrap(URL(string: "https://example.test/page"))

        XCTAssertTrue(
            module.normalTabUserScripts(
                for: url,
                profileId: UUID(),
                isEphemeral: false
            ).isEmpty
        )
        XCTAssertEqual(module.sizeOverride(for: url, profileId: UUID()), 1)
        XCTAssertEqual(probe.storeCount, 0)
    }

    func testDisablingLoadedModuleReleasesRuntimeAndEmitsRefresh() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.boosts)
        let probe = BoostRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)
        var allLivePagesRequests = 0
        module.attach(
            runtime: SumiBoostsModule.Runtime(
                windowOwnedWebView: { _, _ in nil },
                matchingLivePages: { _, _ in [] },
                allLivePages: {
                    allLivePagesRequests += 1
                    return []
                },
                applyBoostAwareZoom: { _, _ in /* No-op. */ },
                openWebInspector: { _, _ in /* No-op. */ },
                sidebarPosition: { .left },
                settings: { nil },
                windowRegistry: { nil }
            )
        )
        var refreshCount = 0
        let cancellable = module.changesPublisher.sink {
            refreshCount += 1
        }
        defer { cancellable.cancel() }

        _ = module.changedBoosts(for: URL(string: "https://example.test/page"), profileId: UUID())
        XCTAssertEqual(probe.storeCount, 1)
        XCTAssertTrue(module.hasLoadedRuntime)

        module.setEnabled(false)

        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(probe.storeCount, 1)
        XCTAssertEqual(allLivePagesRequests, 1)
        XCTAssertEqual(refreshCount, 1)
    }

    private func makeModule(
        registry: SumiModuleRegistry,
        probe: BoostRuntimeProbe
    ) -> SumiBoostsModule {
        SumiBoostsModule(
            moduleRegistry: registry,
            storeFactory: {
                probe.storeCount += 1
                return SumiBoostStore(rootDirectory: self.temporaryDirectory())
            }
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiBoostsModuleTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private final class BoostRuntimeProbe {
    var storeCount = 0
}
