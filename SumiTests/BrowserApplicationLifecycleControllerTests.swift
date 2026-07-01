import XCTest

@testable import Sumi

@MainActor
final class BrowserApplicationLifecycleControllerTests: XCTestCase {
    func testApplicationInactivePausesGeolocationAfterSchedulingMediaReconcile() {
        var events: [String] = []
        let controller = BrowserApplicationLifecycleController(
            dependencies: BrowserApplicationLifecycleController.Dependencies(
                scheduleBackgroundMediaReconcile: { events.append("media:\($0)") },
                pauseGeolocationForApplicationBackgroundIfNeeded: { events.append("pause") },
                resumeGeolocationForApplicationForegroundIfNeeded: { events.append("resume") }
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
                pauseGeolocationForApplicationBackgroundIfNeeded: { events.append("pause") },
                resumeGeolocationForApplicationForegroundIfNeeded: { events.append("resume") }
            )
        )

        controller.handleApplicationDidBecomeActive()

        XCTAssertEqual(events, ["media:app-did-become-active", "resume"])
    }
}
