import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserProfileWebKitBootstrapTests: XCTestCase {
    func testInvalidationRequiresProfileToBePreparedAgain() {
        let profile = Profile(
            name: "Test",
            dataStore: .nonPersistent()
        )
        let bootstrap = BrowserProfileWebKitBootstrap {
            [profile]
        }

        bootstrap.prepareForeground(profile)
        XCTAssertTrue(bootstrap.isPrepared(profile))

        bootstrap.invalidate(profileID: profile.id)
        XCTAssertFalse(bootstrap.isPrepared(profile))

        bootstrap.prepareForeground(profile)
        XCTAssertTrue(bootstrap.isPrepared(profile))
    }

    func testBackgroundPreparationIsGenerationBound() async {
        let profile = Profile(
            name: "Test",
            dataStore: .nonPersistent()
        )
        let bootstrap = BrowserProfileWebKitBootstrap {
            [profile]
        }

        bootstrap.prepareAfterFirstPaint(profileIDs: [profile.id])
        bootstrap.invalidate()
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(bootstrap.isPrepared(profile))
    }
}
