import XCTest

@testable import Sumi

final class URLBarTrackingProtectionPresenterTests: XCTestCase {
    func testPresenterForEnabledPolicyUsesFilledShieldToggle() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true,
                source: .global
            )
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
            )
        )

        XCTAssertNil(presenter.rowSubtitle)
        XCTAssertEqual(presenter.shieldIcon.chromeIconName, "tracking-protection")
        XCTAssertEqual(presenter.shieldIcon.fallbackSystemName, "shield")
        XCTAssertFalse(presenter.shieldIcon.showsCheckmark)
        XCTAssertEqual(presenter.shieldAccessibilityLabel, "Enable Tracking Protection for this site")
        XCTAssertEqual(presenter.shieldAccessibilityValue, "Off")
    }

    func testPresenterDoesNotExposeLegacyURLHubMenuSubtitleOrDetailsText() {
        let presenter = URLBarTrackingProtectionPresenter.make(
            policy: SumiTrackingProtectionEffectivePolicy(
                host: "example.com",
                isEnabled: true,
                source: .global
            )
        )
        let visibleText = presenter.visibleStrings.joined(separator: "\n")

        XCTAssertFalse(visibleText.contains("Use Global Setting"))
        XCTAssertFalse(visibleText.contains("Tracking Protection On"))
        XCTAssertFalse(visibleText.contains("Tracking Protection Off"))
        XCTAssertFalse(visibleText.contains("View protection details"))
        XCTAssertFalse(visibleText.contains("Click to see"))
        XCTAssertFalse(visibleText.contains("Source"))
        XCTAssertFalse(visibleText.contains("Disable for this site"))
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
}
