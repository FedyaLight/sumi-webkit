import CoreLocation
import Foundation

@MainActor
protocol SumiCoreLocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    func setDelegate(_ delegate: CLLocationManagerDelegate?)
    func requestLocation()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: SumiCoreLocationManaging {
    func setDelegate(_ delegate: CLLocationManagerDelegate?) {
        self.delegate = delegate
    }
}

@MainActor
protocol SumiGeolocationServicing: AnyObject {
    var currentLocation: CLLocation? { get }
    var isUpdatingLocation: Bool { get }

    func requestCurrentLocation(
        highAccuracy: Bool,
        timeout: TimeInterval
    ) async -> Result<CLLocation, SumiGeolocationProviderError>

    func startUpdatingLocation(
        highAccuracy: Bool,
        handler: @escaping @MainActor (Result<CLLocation, SumiGeolocationProviderError>) -> Void
    ) async -> SumiGeolocationProviderError?

    func stopUpdatingLocation()
}

@MainActor
final class SumiGeolocationService: NSObject, SumiGeolocationServicing, @preconcurrency CLLocationManagerDelegate {
    private let locationManager: any SumiCoreLocationManaging
    private let systemPermissionService: any SumiSystemPermissionService
    private var updateHandler: (@MainActor (Result<CLLocation, SumiGeolocationProviderError>) -> Void)?
    private var currentLocationContinuation: CheckedContinuation<Result<CLLocation, SumiGeolocationProviderError>, Never>?
    private var currentLocationTimeoutTask: Task<Void, Never>?

    private(set) var currentLocation: CLLocation?
    private(set) var isUpdatingLocation = false

    init(
        locationManager: any SumiCoreLocationManaging = CLLocationManager(),
        systemPermissionService: any SumiSystemPermissionService = MacSumiSystemPermissionService()
    ) {
        self.locationManager = locationManager
        self.systemPermissionService = systemPermissionService
        super.init()
        self.locationManager.setDelegate(self)
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        currentLocationTimeoutTask?.cancel()
        Task { @MainActor [locationManager] in
            locationManager.stopUpdatingLocation()
            locationManager.setDelegate(nil)
        }
    }

    func requestCurrentLocation(
        highAccuracy: Bool,
        timeout: TimeInterval = 10
    ) async -> Result<CLLocation, SumiGeolocationProviderError> {
        if let currentLocation {
            return .success(currentLocation)
        }

        if let error = await preflightError() {
            return .failure(error)
        }

        currentLocationContinuation?.resume(returning: .failure(.unavailable))
        currentLocationTimeoutTask?.cancel()
        currentLocationContinuation = nil

        locationManager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters

        return await withCheckedContinuation { continuation in
            currentLocationContinuation = continuation
            let timeoutNanoseconds = UInt64(max(0.1, timeout) * 1_000_000_000)
            currentLocationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let self, !Task.isCancelled else { return }
                self.finishCurrentLocationRequest(.failure(.timeout))
            }
            locationManager.requestLocation()
        }
    }

    func startUpdatingLocation(
        highAccuracy: Bool,
        handler: @escaping @MainActor (Result<CLLocation, SumiGeolocationProviderError>) -> Void
    ) async -> SumiGeolocationProviderError? {
        if let error = await preflightError() {
            handler(.failure(error))
            return error
        }

        updateHandler = handler
        locationManager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true

        if let currentLocation {
            handler(.success(currentLocation))
        }
        return nil
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateHandler = nil
        isUpdatingLocation = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let error = Self.providerError(for: manager.authorizationStatus, locationServicesEnabled: true)
        if let error {
            updateHandler?(.failure(error))
            finishCurrentLocationRequest(.failure(error))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        let error = Self.providerError(for: status, locationServicesEnabled: true)
        if let error {
            updateHandler?(.failure(error))
            finishCurrentLocationRequest(.failure(error))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateHandler?(.success(location))
        finishCurrentLocationRequest(.success(location))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let providerError = Self.providerError(for: error)
        updateHandler?(.failure(providerError))
        finishCurrentLocationRequest(.failure(providerError))
    }

    private func preflightError() async -> SumiGeolocationProviderError? {
        let snapshot = await systemPermissionService.authorizationSnapshot(for: .geolocation)
        switch snapshot.state {
        case .authorized:
            return nil
        case .systemDisabled:
            return .systemDisabled
        case .denied, .restricted, .notDetermined:
            return .permissionDenied
        case .unavailable, .missingUsageDescription, .missingEntitlement:
            return .unavailable
        }
    }

    private func finishCurrentLocationRequest(
        _ result: Result<CLLocation, SumiGeolocationProviderError>
    ) {
        currentLocationTimeoutTask?.cancel()
        currentLocationTimeoutTask = nil
        guard let continuation = currentLocationContinuation else { return }
        currentLocationContinuation = nil
        continuation.resume(returning: result)
    }

    static func providerError(
        for error: Error
    ) -> SumiGeolocationProviderError {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                return .permissionDenied
            case .locationUnknown, .network, .headingFailure, .rangingUnavailable, .rangingFailure:
                return .unavailable
            default:
                return .unknown(clError.localizedDescription)
            }
        }
        return .unknown(error.localizedDescription)
    }

    static func providerError(
        for status: CLAuthorizationStatus,
        locationServicesEnabled: Bool
    ) -> SumiGeolocationProviderError? {
        guard locationServicesEnabled else { return .systemDisabled }
        switch Int(status.rawValue) {
        case 0:
            return .permissionDenied
        case 1, 2:
            return .permissionDenied
        case 3, 4:
            return nil
        default:
            return .unavailable
        }
    }
}
