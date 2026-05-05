import CoreLocation
import Foundation

@MainActor
protocol SumiCoreLocationManaging: AnyObject {
    var desiredAccuracy: CLLocationAccuracy { get set }
    func setDelegate(_ delegate: CLLocationManagerDelegate?)
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
    private var currentLocation: CLLocation?

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
        Task { @MainActor [locationManager] in
            locationManager.stopUpdatingLocation()
            locationManager.setDelegate(nil)
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

        if let currentLocation {
            handler(.success(currentLocation))
        }
        return nil
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateHandler = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let error = Self.providerError(for: manager.authorizationStatus, locationServicesEnabled: true)
        if let error {
            updateHandler?(.failure(error))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        let error = Self.providerError(for: status, locationServicesEnabled: true)
        if let error {
            updateHandler?(.failure(error))
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateHandler?(.success(location))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let providerError = Self.providerError(for: error)
        updateHandler?(.failure(providerError))
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
