import XCTest

@testable import Sumi

final class SumiPrivacyConfigurationTests: XCTestCase {
    func testContentBlockingFlagIsReportedThroughSumiPrivacyConfig() {
        let manager = SumiContentBlockingPrivacyConfigurationManager(isContentBlockingEnabled: true)
        XCTAssertTrue(manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking))

        manager.setContentBlockingEnabled(false)
        XCTAssertFalse(manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking))

        manager.setContentBlockingEnabled(true)
        XCTAssertTrue(manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testDefaultValueDoesNotOverrideExplicitFlag() {
        let disabled = SumiContentBlockingPrivacyConfiguration(isContentBlockingEnabled: false)
        XCTAssertFalse(disabled.isEnabled(featureKey: .contentBlocking, defaultValue: true))

        let enabled = SumiContentBlockingPrivacyConfiguration(isContentBlockingEnabled: true)
        XCTAssertTrue(enabled.isEnabled(featureKey: .contentBlocking, defaultValue: false))
    }

    func testSettingSameValueKeepsCurrentConfiguration() {
        let manager = SumiContentBlockingPrivacyConfigurationManager(isContentBlockingEnabled: true)
        manager.setContentBlockingEnabled(true)
        XCTAssertTrue(manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testConcurrentTogglesAndReadsAreThreadSafe() {
        let manager = SumiContentBlockingPrivacyConfigurationManager(isContentBlockingEnabled: false)

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration.isMultiple(of: 2) {
                manager.setContentBlockingEnabled(iteration.isMultiple(of: 4))
            } else {
                _ = manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking)
            }
        }

        manager.setContentBlockingEnabled(true)
        XCTAssertTrue(manager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking))
    }
}
