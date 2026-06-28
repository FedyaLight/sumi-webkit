import AVFoundation
import CoreLocation
import UserNotifications
import XCTest

@testable import Sumi

final class SumiSystemPermissionMappingTests: XCTestCase {
    func testAVCaptureAuthorizationStatusesMapCorrectly() {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.avCapture(.notDetermined),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.avCapture(.authorized),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.avCapture(.denied),
            .denied
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.avCapture(.restricted),
            .restricted
        )

        if let unknownStatus = AVAuthorizationStatus(rawValue: 999) {
            XCTAssertEqual(
                SumiSystemPermissionAuthorizationMapper.avCapture(unknownStatus),
                .unavailable
            )
        }
    }

    func testCoreLocationAuthorizationAndGlobalServicesMapCorrectly() throws {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 0),
                locationServicesEnabled: true
            ),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 1),
                locationServicesEnabled: true
            ),
            .restricted
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 2),
                locationServicesEnabled: true
            ),
            .denied
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 3),
                locationServicesEnabled: true
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 4),
                locationServicesEnabled: true
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 999),
                locationServicesEnabled: true
            ),
            .unavailable
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                try coreLocationStatus(rawValue: 2),
                locationServicesEnabled: false
            ),
            .systemDisabled
        )
    }

    func testNotificationAuthorizationStatusesMapCorrectly() throws {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 0)
            ),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 1)
            ),
            .denied
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 2)
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 3)
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 4)
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                try notificationStatus(rawValue: 999)
            ),
            .unavailable
        )
    }

    func testScreenCaptureAuthorizationMappingUsesCoreGraphicsPreflightSemantics() {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCapturePreflight(isAuthorized: true),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCapturePreflight(isAuthorized: false),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCaptureRequest(granted: true),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCaptureRequest(granted: false),
            .denied
        )
    }

    private func coreLocationStatus(rawValue: Int32) throws -> CLAuthorizationStatus {
        try XCTUnwrap(CLAuthorizationStatus(rawValue: rawValue))
    }

    private func notificationStatus(rawValue: Int) throws -> UNAuthorizationStatus {
        try XCTUnwrap(UNAuthorizationStatus(rawValue: rawValue))
    }
}
