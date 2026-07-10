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
        browser.tabManager.spaceStateOwner.replaceSpaces([space])
        browser.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let opener = browser.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.test/opener",
            in: space,
            activate: true
        )

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
            browser.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
        XCTAssertTrue(browser.auxiliaryWindows.sessions.sessionsSnapshot().isEmpty)
    }
}
