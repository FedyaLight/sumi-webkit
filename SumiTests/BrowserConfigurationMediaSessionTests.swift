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

    func testRegularProfileKeepsDDGMediaAndFullscreenPreferencesEnabled() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://www.youtube.com/watch?v=M3ozIvoCFzw")
        )

        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)

        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            XCTAssertEqual(
                configuration.preferences.value(forKey: "allowsPictureInPictureMediaPlayback") as? Bool,
                true
            )
        }
    }

    func testEphemeralProfileKeepsMediaSessionEnabled() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile.createEphemeral()

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: nil
        )

        XCTAssertEqual(
            configuration.preferences.value(forKey: "mediaSessionEnabled") as? Bool,
            true
        )
    }

    func testAuxiliaryNonPersistentConfigurationKeepsMediaSessionEnabledByDefault() {
        let browserConfiguration = BrowserConfiguration()

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .glance
        )

        XCTAssertEqual(
            configuration.preferences.value(forKey: "mediaSessionEnabled") as? Bool,
            true
        )
    }
}
