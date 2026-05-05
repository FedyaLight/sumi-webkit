import XCTest

@testable import Sumi

final class URLBarTrackingProtectionPresenterTests: XCTestCase {
    func testPresenterForEnabledPolicyUsesFilledShieldToggle() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true,
                source: .global
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
                isEnabled: false,
                source: .siteOverride(.disabled)
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
                isEnabled: true,
                source: .global
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
                isEnabled: false,
                source: .siteOverride(.disabled)
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
                isEnabled: true,
                source: .global
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
                    isEnabled: false,
                    source: .global
                )
            ),
            .enabled
        )

        XCTAssertEqual(
            URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(
                for: SumiTrackingProtectionEffectivePolicy(
                    host: "example.com",
                    isEnabled: true,
                    source: .global
                )
            ),
            .disabled
        )
    }

    func testURLBarSourceKeepsControlsModuleGatedAndManualReloadOnly() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(source.contains("effectivePolicyIfEnabled(for: url)"))
        XCTAssertTrue(source.contains("case .tracking(let policy, _, _)"))
        XCTAssertTrue(source.contains("siteOverrideAfterToggle(for: policy)"))
        XCTAssertTrue(source.contains("Reload required"))
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
