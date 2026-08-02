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

        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            XCTAssertEqual(
                configuration.preferences.value(forKey: "allowsPictureInPictureMediaPlayback") as? Bool,
                true
            )
        }
    }

}
