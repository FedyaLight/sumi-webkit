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
                CLAuthorizationStatus(rawValue: 0)!,
                locationServicesEnabled: true
            ),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 1)!,
                locationServicesEnabled: true
            ),
            .restricted
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 2)!,
                locationServicesEnabled: true
            ),
            .denied
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 3)!,
                locationServicesEnabled: true
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 4)!,
                locationServicesEnabled: true
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 999)!,
                locationServicesEnabled: true
            ),
            .unavailable
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.coreLocation(
                CLAuthorizationStatus(rawValue: 2)!,
                locationServicesEnabled: false
            ),
            .systemDisabled
        )
    }

    func testNotificationAuthorizationStatusesMapCorrectly() {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 0)!
            ),
            .notDetermined
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 1)!
            ),
            .denied
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 2)!
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 3)!
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 4)!
            ),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.notifications(
                UNAuthorizationStatus(rawValue: 999)!
            ),
            .unavailable
        )
    }
}
