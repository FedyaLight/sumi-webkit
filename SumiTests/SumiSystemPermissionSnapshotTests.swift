import XCTest

@testable import Sumi

final class SumiSystemPermissionSnapshotTests: XCTestCase {
    func testSnapshotIncludesKindStateFlagsAndReason() {
        for kind in SumiSystemPermissionKind.allCases {
            for state in SumiSystemPermissionAuthorizationState.allCases {
                let snapshot = SumiSystemPermissionSnapshot(kind: kind, state: state)

                XCTAssertEqual(snapshot.kind, kind)
                XCTAssertEqual(snapshot.state, state)
                XCTAssertEqual(snapshot.canRequestFromSystem, state == .notDetermined)
                XCTAssertEqual(
                    snapshot.shouldOpenSystemSettings,
                    [.denied, .restricted, .systemDisabled].contains(state)
                )
                XCTAssertFalse(snapshot.reason.isEmpty)
            }
        }
    }

    func testFakeServiceSnapshotUsesCurrentState() async {
        let service = FakeSumiSystemPermissionService(
            states: [.geolocation: .systemDisabled]
        )

        let snapshot = await service.authorizationSnapshot(for: .geolocation)

        XCTAssertEqual(snapshot.kind, .geolocation)
        XCTAssertEqual(snapshot.state, .systemDisabled)
        XCTAssertFalse(snapshot.canRequestFromSystem)
        XCTAssertTrue(snapshot.shouldOpenSystemSettings)
        XCTAssertFalse(snapshot.reason.isEmpty)
    }

    func testSnapshotSerializesIntoPermissionDecisionSystemAuthorizationSnapshot() throws {
        let snapshot = SumiSystemPermissionSnapshot(kind: .camera, state: .denied)
        let data = try JSONEncoder().encode(snapshot)
        let snapshotString = try XCTUnwrap(String(data: data, encoding: .utf8))

        let decision = SumiPermissionDecision(
            state: .ask,
            persistence: .persistent,
            source: .system,
            reason: "system-authorization-required",
            systemAuthorizationSnapshot: snapshotString
        )

        XCTAssertEqual(decision.systemAuthorizationSnapshot, snapshotString)

        let decodedSnapshot = try JSONDecoder().decode(
            SumiSystemPermissionSnapshot.self,
            from: Data(snapshotString.utf8)
        )
        XCTAssertEqual(decodedSnapshot, snapshot)
    }
}
