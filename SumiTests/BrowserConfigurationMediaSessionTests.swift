import XCTest
@testable import Sumi

@MainActor
final class BrowserConfigurationMediaSessionTests: XCTestCase {
    func testRegularProfileEnablesMediaSession() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )

        XCTAssertEqual(
            configuration.preferences.value(forKey: "mediaSessionEnabled") as? Bool,
            true
        )
    }

    func testEphemeralProfileDisablesMediaSession() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile.createEphemeral()

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )

        XCTAssertEqual(
            configuration.preferences.value(forKey: "mediaSessionEnabled") as? Bool,
            false
        )
    }
}
