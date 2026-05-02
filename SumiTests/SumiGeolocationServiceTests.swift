import CoreLocation
import XCTest

@testable import Sumi

@MainActor
final class SumiGeolocationServiceTests: XCTestCase {
    func testNotDeterminedSystemStateFailsClosedWithoutRequestingAuthorization() async {
        let manager = FakeCoreLocationManager()
        let systemService = FakeSumiSystemPermissionService(states: [.geolocation: .notDetermined])
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: systemService
        )

        var callbackError: SumiGeolocationProviderError?
        let error = await service.startUpdatingLocation(highAccuracy: false) { result in
            callbackError = result.failureValue
        }

        XCTAssertEqual(error, .permissionDenied)
        XCTAssertEqual(callbackError, .permissionDenied)
        XCTAssertEqual(manager.startUpdatingLocationCallCount, 0)
        let authorizationRequestCount = await systemService.requestAuthorizationCallCount(for: .geolocation)
        XCTAssertEqual(authorizationRequestCount, 0)
    }

    func testSystemDisabledMapsToDeterministicError() async {
        let manager = FakeCoreLocationManager()
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: FakeSumiSystemPermissionService(states: [.geolocation: .systemDisabled])
        )

        let error = await service.startUpdatingLocation(highAccuracy: false) { _ in }

        XCTAssertEqual(error, .systemDisabled)
        XCTAssertEqual(manager.startUpdatingLocationCallCount, 0)
    }

    func testStartAndStopUpdatingLocationUseFakeManagerOnly() async {
        let manager = FakeCoreLocationManager()
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: FakeSumiSystemPermissionService(states: [.geolocation: .authorized])
        )
        let expectation = XCTestExpectation(description: "Location update")
        var receivedLocation: CLLocation?

        let error = await service.startUpdatingLocation(highAccuracy: true) { result in
            receivedLocation = try? result.get()
            expectation.fulfill()
        }
        manager.emit(CLLocation(latitude: 1, longitude: 2))

        await fulfillment(of: [expectation], timeout: 1)
        service.stopUpdatingLocation()

        XCTAssertNil(error)
        XCTAssertEqual(receivedLocation?.coordinate.latitude, 1)
        XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
        XCTAssertEqual(manager.stopUpdatingLocationCallCount, 1)
    }
}

@MainActor
private final class FakeCoreLocationManager: SumiCoreLocationManaging {
    weak var delegate: CLLocationManagerDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private(set) var startUpdatingLocationCallCount = 0
    private(set) var stopUpdatingLocationCallCount = 0

    func setDelegate(_ delegate: CLLocationManagerDelegate?) {
        self.delegate = delegate
    }

    func startUpdatingLocation() {
        startUpdatingLocationCallCount += 1
    }

    func stopUpdatingLocation() {
        stopUpdatingLocationCallCount += 1
    }

    func emit(_ location: CLLocation) {
        delegate?.locationManager?(CLLocationManager(), didUpdateLocations: [location])
    }

    func emitFailure(_ error: Error) {
        delegate?.locationManager?(CLLocationManager(), didFailWithError: error)
    }
}

private extension Result where Failure == SumiGeolocationProviderError {
    var failureValue: SumiGeolocationProviderError? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
