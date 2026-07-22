import WebKit
import XCTest

@testable import Sumi

@MainActor
final class AuxiliaryWindowFailureTests: XCTestCase {
    func testPopupFailsBeforeCreatingTabWhenWebViewOwnershipIsUnavailable() {
        let browser = BrowserManager()
        let profile = Profile(name: "Auxiliary failure")
        let space = Space(name: "Auxiliary failure", profileId: profile.id)
        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)

        let opener = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://example.test/opener",
            in: space,
            activate: true
        )
        browser.shutdownCleanupService
            .cleanupAfterBrowserRuntimeDeallocation()

        XCTAssertNil(
            browser.auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(
                    url: URL(string: "https://example.test/popup")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: opener
            )
        )
        XCTAssertTrue(
            browser.tabCollectionMembershipOwner.allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertTrue(browser.auxiliaryWindows.sessions.sessionsSnapshot().isEmpty)
    }
}
