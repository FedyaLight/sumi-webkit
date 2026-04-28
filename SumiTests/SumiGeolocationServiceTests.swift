import CoreLocation
import XCTest

@testable import Sumi

@MainActor
final class SumiGeolocationServiceTests: XCTestCase {
    func testRequestCurrentLocationReturnsFakeLocationWhenSystemAuthorized() async {
        let manager = FakeCoreLocationManager()
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: FakeSumiSystemPermissionService(states: [.geolocation: .authorized])
        )
        let location = CLLocation(latitude: 37.3317, longitude: -122.0301)

        let task = Task { @MainActor in
            await service.requestCurrentLocation(highAccuracy: true, timeout: 1)
        }
        await waitUntil { manager.requestLocationCallCount == 1 }
        manager.emit(location)

        let result = await task.value
        XCTAssertEqual(manager.requestLocationCallCount, 1)
        XCTAssertEqual(manager.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(try? result.get().coordinate.latitude, location.coordinate.latitude)
        XCTAssertEqual(try? result.get().coordinate.longitude, location.coordinate.longitude)
    }

    func testDeniedSystemStateDoesNotRequestRealAuthorizationOrLocation() async {
        let manager = FakeCoreLocationManager()
        let systemService = FakeSumiSystemPermissionService(states: [.geolocation: .denied])
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: systemService
        )

        let result = await service.requestCurrentLocation(highAccuracy: false, timeout: 0.01)

        XCTAssertEqual(result.failureValue, .permissionDenied)
        XCTAssertEqual(manager.requestLocationCallCount, 0)
        let authorizationRequestCount = await systemService.requestAuthorizationCallCount(for: .geolocation)
        XCTAssertEqual(authorizationRequestCount, 0)
    }

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
        XCTAssertFalse(service.isUpdatingLocation)
    }

    func testCurrentLocationRequestTimesOutDeterministically() async {
        let manager = FakeCoreLocationManager()
        let service = SumiGeolocationService(
            locationManager: manager,
            systemPermissionService: FakeSumiSystemPermissionService(states: [.geolocation: .authorized])
        )

        let result = await service.requestCurrentLocation(highAccuracy: false, timeout: 0.01)

        XCTAssertEqual(result.failureValue, .timeout)
        XCTAssertEqual(manager.requestLocationCallCount, 1)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 250_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        var elapsed: UInt64 = 0
        while !condition(), elapsed < timeoutNanoseconds {
            let step: UInt64 = 1_000_000
            try? await Task.sleep(nanoseconds: step)
            elapsed += step
        }
    }
}

@MainActor
private final class FakeCoreLocationManager: SumiCoreLocationManaging {
    weak var delegate: CLLocationManagerDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private(set) var requestLocationCallCount = 0
    private(set) var startUpdatingLocationCallCount = 0
    private(set) var stopUpdatingLocationCallCount = 0

    func setDelegate(_ delegate: CLLocationManagerDelegate?) {
        self.delegate = delegate
    }

    func requestLocation() {
        requestLocationCallCount += 1
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
