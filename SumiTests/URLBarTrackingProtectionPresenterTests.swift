import XCTest

@testable import Sumi

final class URLBarTrackingProtectionPresenterTests: XCTestCase {
    func testPresenterForEnabledPolicyUsesFilledShieldToggle() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true
            ),
            isReloadRequired: false
        )

        XCTAssertEqual(presenter.rowTitle, "Tracking Protection")
        XCTAssertNil(presenter.rowSubtitle)
        XCTAssertEqual(presenter.shieldIcon.chromeIconName, "shield.fill")
        XCTAssertEqual(presenter.shieldIcon.fallbackSystemName, "shield.fill")
        XCTAssertTrue(presenter.shieldIcon.showsCheckmark)
        XCTAssertEqual(presenter.shieldAccessibilityLabel, "Disable Tracking Protection for this site")
        XCTAssertEqual(presenter.shieldAccessibilityValue, "On")
    }

    func testPresenterForDisabledPolicyUsesOutlineShieldToggle() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: false
            ),
            isReloadRequired: false
        )

        XCTAssertNil(presenter.rowSubtitle)
        XCTAssertEqual(presenter.shieldIcon.chromeIconName, "tracking-protection")
        XCTAssertEqual(presenter.shieldIcon.fallbackSystemName, "shield")
        XCTAssertFalse(presenter.shieldIcon.showsCheckmark)
        XCTAssertEqual(presenter.shieldAccessibilityLabel, "Enable Tracking Protection for this site")
        XCTAssertEqual(presenter.shieldAccessibilityValue, "Off")
    }

    func testPresenterDoesNotExposeModeChoiceStrings() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true
            ),
            isReloadRequired: false
        )
        let visibleText = visibleStrings(for: presenter).joined(separator: "\n")

        XCTAssertFalse(visibleText.contains("Use Global Setting"))
        XCTAssertFalse(visibleText.contains("Enable for This Site"))
        XCTAssertFalse(visibleText.contains("Disable for This Site"))
    }

    func testReloadRequiredStateAppearsInPresenter() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: false
            ),
            isReloadRequired: true
        )

        XCTAssertEqual(presenter.rowSubtitle, "Reload required")
        XCTAssertTrue(visibleStrings(for: presenter).contains("Reload required"))
        XCTAssertFalse(visibleStrings(for: presenter).contains("Reload"))
    }

    func testPresenterDoesNotExposeLegacyURLHubDetailsText() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true
            ),
            isReloadRequired: false
        )
        let visibleText = visibleStrings(for: presenter).joined(separator: "\n")

        XCTAssertFalse(visibleText.contains("Use Global Setting"))
        XCTAssertFalse(visibleText.contains("Enable for This Site"))
        XCTAssertFalse(visibleText.contains("Disable for This Site"))
        XCTAssertFalse(visibleText.contains("Tracking Protection On"))
        XCTAssertFalse(visibleText.contains("Tracking Protection Off"))
        XCTAssertFalse(visibleText.contains("View protection details"))
        XCTAssertFalse(visibleText.contains("Click to see"))
        XCTAssertFalse(visibleText.contains("Source"))
        XCTAssertFalse(visibleText.contains("No tracker activity"))
        XCTAssertFalse(visibleText.contains("Reload to apply changes"))
    }

    func testToggleOverrideSemanticsUseCurrentEffectivePolicyOnly() {
        XCTAssertEqual(
            URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(
                for: SumiTrackingProtectionEffectivePolicy(
                    host: "example.com",
                    isEnabled: false
                )
            ),
            .enabled
        )

        XCTAssertEqual(
            URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(
                for: SumiTrackingProtectionEffectivePolicy(
                    host: "example.com",
                    isEnabled: true
                )
            ),
            .disabled
        )
    }

    func testAdblockPresenterShowsGloballyOffStateWithoutActiveProtection() {
        let presenter = URLBarAdblockPresenter.make(
            policy: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false),
            isGlobalEnabled: false,
            isReloadRequired: false
        )

        XCTAssertEqual(presenter.rowTitle, "Ad Blocking")
        XCTAssertEqual(presenter.rowSubtitle, "Off globally")
        XCTAssertFalse(presenter.isEnabled)
        XCTAssertFalse(presenter.isInteractive)
        XCTAssertEqual(presenter.accessibilityValue, "Off globally")
    }

    func testAdblockPresenterShowsPerSiteStatesWhenGlobalEnabled() {
        let enabled = URLBarAdblockPresenter.make(
            policy: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: true),
            isGlobalEnabled: true,
            isReloadRequired: false
        )
        let disabled = URLBarAdblockPresenter.make(
            policy: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false),
            isGlobalEnabled: true,
            isReloadRequired: false
        )

        XCTAssertEqual(enabled.rowSubtitle, "On for this site")
        XCTAssertTrue(enabled.isInteractive)
        XCTAssertEqual(enabled.accessibilityLabel, "Disable Ad Blocking for this site")
        XCTAssertEqual(disabled.rowSubtitle, "Off for this site")
        XCTAssertEqual(disabled.accessibilityLabel, "Enable Ad Blocking for this site")
    }

    func testAdblockPresenterShowsReloadRequiredWithoutReloadActionCopy() {
        let presenter = URLBarAdblockPresenter.make(
            policy: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false),
            isGlobalEnabled: true,
            isReloadRequired: true
        )

        XCTAssertEqual(presenter.rowSubtitle, "Reload required")
        XCTAssertFalse([presenter.rowTitle, presenter.rowSubtitle].joined(separator: "\n").contains("Reload to apply"))
    }

    func testAdblockToggleOverrideSemanticsUseCurrentEffectivePolicyOnly() {
        XCTAssertEqual(
            URLBarAdblockPresenter.siteOverrideAfterToggle(
                for: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false)
            ),
            .allowed
        )
        XCTAssertEqual(
            URLBarAdblockPresenter.siteOverrideAfterToggle(
                for: SumiAdblockEffectivePolicy(host: "example.com", isEnabled: true)
            ),
            .disabled
        )
    }

    @MainActor
    func testURLHubSnapshotShowsAdblockGloballyOffWithoutRuntimeDecision() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: harness.defaults) },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        let snapshot = SiteControlsSnapshot.resolve(
            url: URL(string: "https://www.example.com/path")!,
            profile: nil,
            adBlockingModule: module
        )

        let row = snapshot.settingsRows.first { $0.id == "ad-blocking" }
        XCTAssertEqual(row?.title, "Ad Blocking")
        XCTAssertEqual(row?.subtitle, "Off globally")
        XCTAssertTrue(row?.isDisabled == true)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubSnapshotUsesSameAdblockSitePolicyStoreAsSettings() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let siteStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        _ = siteStore.setSiteOverride(.disabled, forUserInput: "https://www.example.com/path?query=1")
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { siteStore }
        )

        let snapshot = SiteControlsSnapshot.resolve(
            url: URL(string: "https://example.com/other")!,
            profile: nil,
            adBlockingModule: module
        )
        let row = snapshot.settingsRows.first { $0.id == "ad-blocking" }

        XCTAssertEqual(row?.subtitle, "Off for this site")
        XCTAssertEqual(siteStore.sortedSiteOverrides.map(\.host), ["example.com"])
    }

    @MainActor
    func testNonWebURLHubSnapshotDoesNotShowMisleadingAdblockActiveState() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        let snapshot = SiteControlsSnapshot.resolve(
            url: URL(string: "about:blank")!,
            profile: nil,
            adBlockingModule: module
        )

        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "ad-blocking" })
    }

    func testURLBarSourceKeepsControlsModuleGatedAndManualReloadOnly() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(source.contains("effectivePolicyIfEnabled(for: url)"))
        XCTAssertTrue(source.contains("case .tracking(let policy, _, _)"))
        XCTAssertTrue(source.contains("case .adBlocking(let policy, _, let globalEnabled, _)"))
        XCTAssertTrue(source.contains("browserManager.adBlockingModule.setSiteOverride"))
        XCTAssertTrue(source.contains("currentTab.markAdblockReloadRequiredIfNeeded"))
        XCTAssertTrue(source.contains("siteOverrideAfterToggle(for: policy)"))
        XCTAssertTrue(source.contains("Reload required"))
        XCTAssertTrue(source.contains("Off globally"))
        XCTAssertFalse(source.contains("adBlockingModule.normalTabDecision"))
        XCTAssertTrue(source.contains("currentTab.markTrackingProtectionReloadRequiredIfNeeded"))
        XCTAssertFalse(source.contains("Use Global Setting"))
        XCTAssertFalse(source.contains("Enable for This Site"))
        XCTAssertFalse(source.contains("Disable for This Site"))
        XCTAssertFalse(source.contains("overrideChoices"))
        XCTAssertFalse(source.contains("trackingReloadAction"))
        XCTAssertFalse(source.contains("Button(\"Reload\")"))
        XCTAssertFalse(source.contains("currentTab?.refresh()"))
        XCTAssertFalse(source.contains("checkmark.circle.fill"))
        XCTAssertFalse(source.contains("Image(systemName: presenter.isEnabled ?"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("unified site settings"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("onboarding"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("stale tracker"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("automatic tracker"))
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func visibleStrings(for presenter: URLBarTrackingProtectionPresenter) -> [String] {
        var strings = [
            presenter.rowTitle,
        ]
        if let rowSubtitle = presenter.rowSubtitle {
            strings.append(rowSubtitle)
        }
        return strings
    }
}
