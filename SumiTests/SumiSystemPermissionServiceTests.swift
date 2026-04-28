import SwiftData
import XCTest

@testable import Sumi

final class SumiSystemPermissionServiceTests: XCTestCase {
    func testFakeCameraStates() async {
        await assertFakeStates(
            kind: .camera,
            states: [
                .authorized,
                .denied,
                .restricted,
                .notDetermined,
                .unavailable,
                .missingUsageDescription,
                .missingEntitlement,
            ]
        )
    }

    func testFakeMicrophoneStates() async {
        await assertFakeStates(
            kind: .microphone,
            states: [
                .authorized,
                .denied,
                .restricted,
                .notDetermined,
                .unavailable,
                .missingUsageDescription,
                .missingEntitlement,
            ]
        )
    }

    func testFakeGeolocationStates() async {
        await assertFakeStates(
            kind: .geolocation,
            states: [
                .authorized,
                .denied,
                .restricted,
                .notDetermined,
                .systemDisabled,
                .unavailable,
                .missingUsageDescription,
                .missingEntitlement,
            ]
        )
    }

    func testFakeNotificationStates() async {
        await assertFakeStates(
            kind: .notifications,
            states: [
                .authorized,
                .denied,
                .restricted,
                .notDetermined,
                .unavailable,
            ]
        )
    }

    func testFakeScreenCaptureStates() async {
        await assertFakeStates(
            kind: .screenCapture,
            states: [
                .authorized,
                .denied,
                .restricted,
                .notDetermined,
                .unavailable,
                .missingEntitlement,
            ]
        )
    }

    func testFakeRequestAuthorizationTransitionsFromNotDeterminedToConfiguredResult() async {
        let service = FakeSumiSystemPermissionService(
            states: [.camera: .notDetermined],
            requestResults: [.camera: .denied]
        )

        let requestedState = await service.requestAuthorization(for: .camera)
        let finalState = await service.authorizationState(for: .camera)

        XCTAssertEqual(requestedState, .denied)
        XCTAssertEqual(finalState, .denied)
    }

    func testFakeRequestAuthorizationDoesNotMutateDeniedOrRestrictedStatesByDefault() async {
        let service = FakeSumiSystemPermissionService(
            states: [
                .camera: .denied,
                .microphone: .restricted,
            ],
            requestResults: [
                .camera: .authorized,
                .microphone: .authorized,
            ]
        )

        let requestedCameraState = await service.requestAuthorization(for: .camera)
        let requestedMicrophoneState = await service.requestAuthorization(for: .microphone)
        let finalCameraState = await service.authorizationState(for: .camera)
        let finalMicrophoneState = await service.authorizationState(for: .microphone)

        XCTAssertEqual(requestedCameraState, .denied)
        XCTAssertEqual(requestedMicrophoneState, .restricted)
        XCTAssertEqual(finalCameraState, .denied)
        XCTAssertEqual(finalMicrophoneState, .restricted)
    }

    func testFakeCanExplicitlyModelRequestingResolvedStates() async {
        let service = FakeSumiSystemPermissionService(
            states: [.camera: .denied],
            requestResults: [.camera: .authorized],
            allowsRequestingResolvedStates: true
        )

        let requestedState = await service.requestAuthorization(for: .camera)
        let finalState = await service.authorizationState(for: .camera)

        XCTAssertEqual(requestedState, .authorized)
        XCTAssertEqual(finalState, .authorized)
    }

    @MainActor
    func testSystemPermissionServiceDoesNotPersistBrowserPermissionDecisions() async throws {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        let service = FakeSumiSystemPermissionService(
            states: [.camera: .notDetermined],
            requestResults: [.camera: .authorized]
        )

        _ = await service.requestAuthorization(for: .camera)

        let records = try await store.listDecisions(profilePartitionId: "profile-a")
        XCTAssertTrue(records.isEmpty)
    }

    private func assertFakeStates(
        kind: SumiSystemPermissionKind,
        states: [SumiSystemPermissionAuthorizationState],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for state in states {
            let service = FakeSumiSystemPermissionService(states: [kind: state])
            let actualState = await service.authorizationState(for: kind)
            XCTAssertEqual(actualState, state, file: file, line: line)
        }
    }
}
