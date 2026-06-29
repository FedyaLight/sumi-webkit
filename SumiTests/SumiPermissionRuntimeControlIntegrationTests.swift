import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionRuntimeControlIntegrationTests: XCTestCase {
    func testActiveCameraRuntimeControlExposesOnlyRuntimeActions() throws {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .active,
                microphone: .none,
                geolocation: .none
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        let camera = try XCTUnwrap(controls.first { $0.id == SumiPermissionType.camera.identity })
        XCTAssertEqual(controls.map(\.id), [SumiPermissionType.camera.identity])
        XCTAssertEqual(camera.actions.map(\.kind), [.muteCamera, .stopCamera])
        XCTAssertEqual(camera.actions.map(\.isDestructive), [false, true])
        XCTAssertNil(camera.disabledReason)
    }

    func testScreenCaptureRuntimeControlIsInformationalOnly() throws {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                screenCapture: .active,
                geolocation: .none
            ),
            reloadRequired: false,
            displayDomain: "screen.example"
        )

        let screenCapture = try XCTUnwrap(
            controls.first { $0.id == SumiPermissionType.screenCapture.identity }
        )
        XCTAssertEqual(controls.map(\.id), [SumiPermissionType.screenCapture.identity])
        XCTAssertEqual(screenCapture.subtitle, SumiPermissionRuntimeControlsStrings.screenSharingControlledByWebKit)
        XCTAssertTrue(screenCapture.actions.isEmpty)
        XCTAssertEqual(screenCapture.disabledReason, screenCapture.subtitle)
    }

    func testAutoplayReloadControlIsOnlyShownWhenReloadRequired() throws {
        XCTAssertTrue(
            SumiPermissionRuntimeControlsViewModel.makeControls(
                runtimeState: nil,
                reloadRequired: false,
                displayDomain: "video.example"
            ).isEmpty
        )

        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: nil,
            reloadRequired: true,
            displayDomain: "video.example"
        )

        let autoplay = try XCTUnwrap(controls.first { $0.id == SumiPermissionType.autoplay.identity })
        XCTAssertEqual(controls.map(\.id), [SumiPermissionType.autoplay.identity])
        XCTAssertEqual(autoplay.actions.map(\.kind), [.reloadAutoplay])
    }
}
