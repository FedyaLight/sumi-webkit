import XCTest

@testable import Sumi

final class SumiScreenCapturePermissionTests: XCTestCase {
    func testScreenCaptureIdentityAndDisplayLabelAreStable() throws {
        let permissionType = SumiPermissionType.screenCapture

        XCTAssertEqual(permissionType.identity, "screen-capture")
        XCTAssertEqual(permissionType.displayLabel, "Screen Sharing")
        XCTAssertEqual(SumiPermissionType(identity: "screen-capture"), .screenCapture)

        let data = try JSONEncoder().encode(permissionType)
        let decoded = try JSONDecoder().decode(SumiPermissionType.self, from: data)
        XCTAssertEqual(decoded, .screenCapture)
    }

    func testScreenCaptureIsSensitivePowerfulAndPersistable() {
        XCTAssertTrue(SumiPermissionType.screenCapture.isSensitivePowerful)
        XCTAssertFalse(SumiPermissionType.screenCapture.isOneTimeOnly)
        XCTAssertTrue(SumiPermissionType.screenCapture.canBePersisted)
        XCTAssertEqual(SumiPermissionType.screenCapture.expandedForPersistence, [.screenCapture])
    }

    func testScreenCaptureKeyIdentityIncludesOriginsProfileAndType() {
        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://share.example/path"),
            topOrigin: SumiPermissionOrigin(string: "https://top.example"),
            permissionType: .screenCapture,
            profilePartitionId: "Profile-A",
            transientPageId: "page-a",
            isEphemeralProfile: false
        )

        XCTAssertEqual(
            key.persistentIdentity,
            "profile-a|https://share.example|https://top.example|screen-capture"
        )
    }

}
