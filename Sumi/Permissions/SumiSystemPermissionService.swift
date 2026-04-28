import AVFoundation
import CoreGraphics
import CoreLocation
import Foundation
import Security
import UserNotifications

protocol SumiSystemPermissionService: Sendable {
    func authorizationState(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState
    func authorizationSnapshot(for kind: SumiSystemPermissionKind) async -> SumiSystemPermissionSnapshot
    func requestAuthorization(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState
    @discardableResult
    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool
    func refreshAuthorizationStates() async
}

extension SumiSystemPermissionService {
    func authorizationSnapshot(for kind: SumiSystemPermissionKind) async -> SumiSystemPermissionSnapshot {
        let state = await authorizationState(for: kind)
        return SumiSystemPermissionSnapshot(kind: kind, state: state)
    }

    func authorizationSnapshots(
        for kinds: [SumiSystemPermissionKind] = SumiSystemPermissionKind.allCases
    ) async -> [SumiSystemPermissionSnapshot] {
        var snapshots: [SumiSystemPermissionSnapshot] = []
        snapshots.reserveCapacity(kinds.count)
        for kind in kinds {
            snapshots.append(await authorizationSnapshot(for: kind))
        }
        return snapshots
    }

    func mediaPreflightAuthorizationSnapshots() async -> [SumiSystemPermissionSnapshot] {
        await authorizationSnapshots(for: [.camera, .microphone])
    }

    func refreshAuthorizationStates() async {}
}

struct MacSumiSystemPermissionService: SumiSystemPermissionService {
    private let entitlementReader: SumiSystemPermissionEntitlementReader
    private let screenCapturePreflightAccess: @Sendable () -> Bool
    private let requestScreenCaptureAccess: @Sendable () -> Bool

    init(
        entitlementReader: SumiSystemPermissionEntitlementReader = .currentProcess,
        screenCapturePreflightAccess: @escaping @Sendable () -> Bool = {
            CGPreflightScreenCaptureAccess()
        },
        requestScreenCaptureAccess: @escaping @Sendable () -> Bool = {
            CGRequestScreenCaptureAccess()
        }
    ) {
        self.entitlementReader = entitlementReader
        self.screenCapturePreflightAccess = screenCapturePreflightAccess
        self.requestScreenCaptureAccess = requestScreenCaptureAccess
    }

    func authorizationState(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        if isMissingUsageDescription(for: kind) {
            return .missingUsageDescription
        }
        if isMissingRequiredEntitlement(for: kind) {
            return .missingEntitlement
        }

        switch kind {
        case .camera:
            guard Self.isCaptureDeviceAvailable(for: .video) else { return .unavailable }
            return SumiSystemPermissionAuthorizationMapper.avCapture(
                AVCaptureDevice.authorizationStatus(for: .video)
            )
        case .microphone:
            guard Self.isCaptureDeviceAvailable(for: .audio) else { return .unavailable }
            return SumiSystemPermissionAuthorizationMapper.avCapture(
                AVCaptureDevice.authorizationStatus(for: .audio)
            )
        case .geolocation:
            return await geolocationAuthorizationState()
        case .notifications:
            return SumiSystemPermissionAuthorizationMapper.notifications(
                await notificationAuthorizationStatus()
            )
        case .screenCapture:
            return SumiSystemPermissionAuthorizationMapper.screenCapturePreflight(
                isAuthorized: screenCapturePreflightAccess()
            )
        }
    }

    func authorizationSnapshot(for kind: SumiSystemPermissionKind) async -> SumiSystemPermissionSnapshot {
        let state = await authorizationState(for: kind)
        if kind == .screenCapture, state == .notDetermined {
            return SumiSystemPermissionSnapshot(
                kind: kind,
                state: state,
                reason: "Screen Recording access is not currently authorized; CoreGraphics preflight cannot distinguish not-determined from denied without requesting."
            )
        }
        return SumiSystemPermissionSnapshot(kind: kind, state: state)
    }

    func requestAuthorization(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        let currentState = await authorizationState(for: kind)
        guard currentState == .notDetermined else {
            return currentState
        }

        switch kind {
        case .camera:
            return await requestCaptureAuthorization(for: .video)
        case .microphone:
            return await requestCaptureAuthorization(for: .audio)
        case .geolocation:
            guard await locationServicesEnabled() else { return .systemDisabled }
            let requester = await SumiLocationAuthorizationRequester()
            let status = await requester.requestAuthorization()
            return await SumiSystemPermissionAuthorizationMapper.coreLocation(
                status,
                locationServicesEnabled: locationServicesEnabled()
            )
        case .notifications:
            return await requestNotificationAuthorization()
        case .screenCapture:
            return SumiSystemPermissionAuthorizationMapper.screenCaptureRequest(
                granted: requestScreenCaptureAccess()
            )
        }
    }

    @discardableResult
    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool {
        await SumiSystemPermissionSettingsLink.open(for: kind)
    }

    private func requestCaptureAuthorization(
        for mediaType: AVMediaType
    ) async -> SumiSystemPermissionAuthorizationState {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { _ in
                let status = AVCaptureDevice.authorizationStatus(for: mediaType)
                continuation.resume(
                    returning: SumiSystemPermissionAuthorizationMapper.avCapture(status)
                )
            }
        }
    }

    private func geolocationAuthorizationState() async -> SumiSystemPermissionAuthorizationState {
        await SumiSystemPermissionAuthorizationMapper.coreLocation(
            currentLocationAuthorizationStatus(),
            locationServicesEnabled: locationServicesEnabled()
        )
    }

    private func currentLocationAuthorizationStatus() async -> CLAuthorizationStatus {
        await MainActor.run {
            CLLocationManager().authorizationStatus
        }
    }

    private func locationServicesEnabled() async -> Bool {
        await MainActor.run {
            CLLocationManager.locationServicesEnabled()
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestNotificationAuthorization() async -> SumiSystemPermissionAuthorizationState {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
                granted,
                error in
                guard error == nil else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    private func isMissingUsageDescription(for kind: SumiSystemPermissionKind) -> Bool {
        for key in kind.requiredUsageDescriptionKeys {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return true
            }
        }
        return false
    }

    private func isMissingRequiredEntitlement(for kind: SumiSystemPermissionKind) -> Bool {
        guard let requiredEntitlement = kind.requiredSandboxEntitlement else { return false }
        guard entitlementReader.boolValue(for: "com.apple.security.app-sandbox") == true else {
            return false
        }
        return entitlementReader.boolValue(for: requiredEntitlement) != true
    }

    private static func isCaptureDeviceAvailable(for mediaType: AVMediaType) -> Bool {
        AVCaptureDevice.default(for: mediaType) != nil
    }
}

enum SumiSystemPermissionAuthorizationMapper {
    static func avCapture(
        _ status: AVAuthorizationStatus
    ) -> SumiSystemPermissionAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    static func coreLocation(
        _ status: CLAuthorizationStatus,
        locationServicesEnabled: Bool
    ) -> SumiSystemPermissionAuthorizationState {
        guard locationServicesEnabled else { return .systemDisabled }

        switch Int(status.rawValue) {
        case 0:
            return .notDetermined
        case 1:
            return .restricted
        case 2:
            return .denied
        case 3, 4:
            return .authorized
        default:
            return .unavailable
        }
    }

    static func notifications(
        _ status: UNAuthorizationStatus
    ) -> SumiSystemPermissionAuthorizationState {
        switch Int(status.rawValue) {
        case 0:
            return .notDetermined
        case 1:
            return .denied
        case 2, 3, 4:
            return .authorized
        default:
            return .unavailable
        }
    }

    static func screenCapturePreflight(
        isAuthorized: Bool
    ) -> SumiSystemPermissionAuthorizationState {
        isAuthorized ? .authorized : .notDetermined
    }

    static func screenCaptureRequest(
        granted: Bool
    ) -> SumiSystemPermissionAuthorizationState {
        granted ? .authorized : .denied
    }
}

struct SumiSystemPermissionEntitlementReader: Sendable {
    private var readBoolValue: @Sendable (_ key: String) -> Bool?

    init(_ readBoolValue: @escaping @Sendable (_ key: String) -> Bool?) {
        self.readBoolValue = readBoolValue
    }

    func boolValue(for key: String) -> Bool? {
        readBoolValue(key)
    }

    static let currentProcess = SumiSystemPermissionEntitlementReader { key in
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil),
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}

private extension SumiSystemPermissionKind {
    var requiredUsageDescriptionKeys: [String] {
        switch self {
        case .camera:
            return ["NSCameraUsageDescription"]
        case .microphone:
            return ["NSMicrophoneUsageDescription"]
        case .geolocation:
            return ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"]
        case .notifications:
            return []
        case .screenCapture:
            return []
        }
    }

    var requiredSandboxEntitlement: String? {
        switch self {
        case .camera:
            return "com.apple.security.device.camera"
        case .microphone:
            return "com.apple.security.device.audio-input"
        case .geolocation:
            return "com.apple.security.personal-information.location"
        case .notifications:
            return nil
        case .screenCapture:
            return nil
        }
    }
}

@MainActor
private final class SumiLocationAuthorizationRequester: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestAuthorization() async -> CLAuthorizationStatus {
        let currentStatus = manager.authorizationStatus
        guard Int(currentStatus.rawValue) == 0 else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        completeIfDetermined(manager.authorizationStatus)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        completeIfDetermined(status)
    }

    private func completeIfDetermined(_ status: CLAuthorizationStatus) {
        guard Int(status.rawValue) != 0,
              let continuation
        else {
            return
        }
        self.continuation = nil
        manager.delegate = nil
        continuation.resume(returning: status)
    }
}
