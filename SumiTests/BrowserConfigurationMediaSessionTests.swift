@testable import Sumi
import XCTest

@MainActor
final class BrowserConfigurationMediaSessionTests: XCTestCase {
    func testRegularProfileKeepsDDGMediaAndFullscreenPreferencesEnabled() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Default")

        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://www.youtube.com/watch?v=M3ozIvoCFzw")
        )

        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)

        let elementFullscreenSetter = NSSelectorFromString(
            "_setVideoFullscreenRequiresElementFullscreen:"
        )
        if configuration.preferences.responds(to: elementFullscreenSetter) {
            XCTAssertEqual(
                configuration.preferences.value(
                    forKey: "videoFullscreenRequiresElementFullscreen"
                ) as? Bool,
                true
            )
        }

        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            XCTAssertEqual(
                configuration.preferences.value(forKey: "allowsPictureInPictureMediaPlayback") as? Bool,
                true
            )
        }
    }
}
