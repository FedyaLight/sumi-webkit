import XCTest

@testable import Sumi

@MainActor
final class AppLifecycleControllerTests: XCTestCase {
    func testApplicationInactivePausesGeolocationAfterSchedulingMediaReconcile() {
        var events: [String] = []
        let controller = BrowserApplicationLifecycleController(
            dependencies: BrowserApplicationLifecycleController.Dependencies(
                scheduleBackgroundMediaReconcile: { events.append("media:\($0)") },
                pauseGeolocationOnAppBackgroundIfNeeded: { events.append("pause") },
                resumeGeolocationOnAppForegroundIfNeeded: { events.append("resume") }
            )
        )

        controller.handleApplicationWillResignActive()

        XCTAssertEqual(events, ["media:app-will-resign-active", "pause"])
    }

    func testApplicationActiveResumesGeolocationAfterSchedulingMediaReconcile() {
        var events: [String] = []
        let controller = BrowserApplicationLifecycleController(
            dependencies: BrowserApplicationLifecycleController.Dependencies(
                scheduleBackgroundMediaReconcile: { events.append("media:\($0)") },
                pauseGeolocationOnAppBackgroundIfNeeded: { events.append("pause") },
                resumeGeolocationOnAppForegroundIfNeeded: { events.append("resume") }
            )
        )

        controller.handleApplicationDidBecomeActive()

        XCTAssertEqual(events, ["media:app-did-become-active", "resume"])
    }
}
