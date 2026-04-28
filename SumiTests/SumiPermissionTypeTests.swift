import XCTest

@testable import Sumi

final class SumiPermissionTypeTests: XCTestCase {
    func testCameraAndMicrophoneExpandsForPersistence() {
        XCTAssertEqual(
            SumiPermissionType.cameraAndMicrophone.expandedForPersistence,
            [.camera, .microphone]
        )
        XCTAssertFalse(SumiPermissionType.cameraAndMicrophone.canBePersisted)
    }

    func testFilePickerReportsOneTimeOnly() {
        XCTAssertTrue(SumiPermissionType.filePicker.isOneTimeOnly)
        XCTAssertFalse(SumiPermissionType.filePicker.canBePersisted)
    }

    func testScreenCaptureMetadataIsStable() {
        XCTAssertEqual(SumiPermissionType.screenCapture.identity, "screen-capture")
        XCTAssertEqual(SumiPermissionType.screenCapture.displayLabel, "Screen Sharing")
        XCTAssertTrue(SumiPermissionType.screenCapture.isSensitivePowerful)
        XCTAssertTrue(SumiPermissionType.screenCapture.canBePersisted)
        XCTAssertFalse(SumiPermissionType.screenCapture.isOneTimeOnly)
    }

    func testExternalSchemeIdentityAndDisplayLabelAreStable() {
        let upper = SumiPermissionType.externalScheme(" MailTo: ")
        let lower = SumiPermissionType.externalScheme("mailto")

        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.identity, "external-scheme:mailto")
        XCTAssertEqual(upper.displayLabel, "Open mailto Links")
    }
}
