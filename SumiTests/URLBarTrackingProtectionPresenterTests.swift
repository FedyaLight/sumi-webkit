import XCTest

@testable import Sumi

final class URLBarTrackingProtectionPresenterTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testURLHubSourceContainsOnlyUnifiedProtectionRow() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(source.contains("id: \"adblock-protection\""))
        XCTAssertTrue(source.contains("title: \"Adblock & Protection\""))
        XCTAssertTrue(source.contains("Restart Sumi to apply global changes"))
        XCTAssertFalse(source.contains("URLBarTrackingProtectionPresenter"))
        XCTAssertFalse(source.contains("URLBarAdblockPresenter"))
        XCTAssertFalse(source.contains("kind: .tracking("))
        XCTAssertFalse(source.contains("kind: .adBlocking("))
    }

    @MainActor
    func testURLHubWithoutCoordinatorDoesNotFallBackToLegacyProtectionRows() {
        let snapshot = SiteControlsSnapshot.resolve(
            url: URL(string: "https://example.com")!,
            profile: nil,
            protectionCoordinator: nil,
            trackingProtectionModule: nil,
            adBlockingModule: nil
        )

        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "tracking-protection" })
        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "ad-blocking" })
        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "adblock-protection" })
    }

    @MainActor
    func testPresenterForEnabledPolicyUsesFilledShieldToggle() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let coordinator = try await makePreparedAdblockCoordinator(defaults: harness.defaults)

        let row = try protectionRow(
            for: URL(string: "https://example.com/page")!,
            coordinator: coordinator
        )

        XCTAssertNil(row.chromeIconName)
        XCTAssertEqual(row.fallbackSystemName, "shield.lefthalf.filled")
        XCTAssertEqual(row.subtitle, SumiProtectionLevel.adblock.displayTitle)
        XCTAssertFalse(row.isDisabled)
        XCTAssertTrue(row.isInteractive)
    }

    @MainActor
    func testToggleOverrideSemanticsUseCurrentEffectivePolicyOnly() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let coordinator = try await makePreparedAdblockCoordinator(defaults: harness.defaults)
        let url = URL(string: "https://example.com/page")!

        coordinator.setSiteOverride(.disabled, for: url)

        let disabledRow = try protectionRow(for: url, coordinator: coordinator)
        XCTAssertEqual(disabledRow.chromeIconName, "shield-off")
        XCTAssertEqual(disabledRow.fallbackSystemName, "shield.slash")
        XCTAssertEqual(disabledRow.subtitle, "Protection off for this site")
        XCTAssertTrue(disabledRow.isInteractive)

        guard case .protection(let disabledPlan, _) = disabledRow.kind else {
            return XCTFail("Expected unified protection row")
        }
        XCTAssertEqual(disabledPlan.siteOverride, .disabled)
        XCTAssertFalse(disabledPlan.sitePolicyAllowsProtection)
        XCTAssertEqual(disabledPlan.effectiveLevel, .off)

        coordinator.setSiteOverride(.inherit, for: url)

        let enabledRow = try protectionRow(for: url, coordinator: coordinator)
        guard case .protection(let enabledPlan, _) = enabledRow.kind else {
            return XCTFail("Expected unified protection row")
        }
        XCTAssertEqual(enabledPlan.siteOverride, .inherit)
        XCTAssertTrue(enabledPlan.sitePolicyAllowsProtection)
        XCTAssertEqual(enabledPlan.effectiveLevel, .adblock)
        XCTAssertNil(enabledRow.chromeIconName)
        XCTAssertEqual(enabledRow.fallbackSystemName, "shield.lefthalf.filled")
    }

    @MainActor
    private func makePreparedAdblockCoordinator(
        defaults: UserDefaults
    ) async throws -> SumiProtectionCoordinator {
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: defaults)
        settings.setAppliedLevel(.adblock)

        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryDirectory(prefix: "URLHubAdblockManifest")
        )
        _ = try await PreparedAdblockTestSupport.seedPreparedManifest(in: manifestStore)

        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: {
                AdblockSitePolicyStore(userDefaults: defaults)
            },
            preparedBundleResourceURL: nil,
            preparedBundleRemoteRootURL: nil,
            preparedBundleGeneratedRootURL: nil,
            ruleListStoreFactory: { settings, isEnabled in
                AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler(),
                    embeddedBundleURLProvider: { nil }
                )
            }
        )
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            trackingProtectionModule: SumiTrackingProtectionModule(moduleRegistry: registry),
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )
        _ = try await adBlockingModule.restorePreparedNativeRuleBundleForStartup(
            profileId: SumiProtectionBundleProfile.adblock
        )
        return coordinator
    }

    @MainActor
    private func protectionRow(
        for url: URL,
        coordinator: SumiProtectionCoordinator
    ) throws -> SiteControlsSettingRowModel {
        let snapshot = SiteControlsSnapshot.resolve(
            url: url,
            profile: nil,
            protectionCoordinator: coordinator
        )
        return try XCTUnwrap(snapshot.settingsRows.first { $0.id == "adblock-protection" })
    }

    private func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
