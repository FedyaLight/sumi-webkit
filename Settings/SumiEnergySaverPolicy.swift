import Foundation
import IOKit.ps

enum SumiEnergySaverMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case automatic
    case on
    case off

    var id: String { rawValue }

    static let settingsOrder: [SumiEnergySaverMode] = [.off, .on, .automatic]

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .on:
            return "On"
        case .off:
            return "Off"
        }
    }
}

enum SumiEnergySaverFeature: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case reduceInterfaceAnimations
    case useOpaqueChromeSurfaces
    case deactivateInactiveTabsSooner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reduceInterfaceAnimations:
            return "Reduce interface animations"
        case .useOpaqueChromeSurfaces:
            return "Use opaque browser chrome"
        case .deactivateInactiveTabsSooner:
            return "Deactivate inactive tabs sooner"
        }
    }

    var subtitle: String {
        switch self {
        case .reduceInterfaceAnimations:
            return "Keeps direct manipulation responsive while removing non-essential transitions."
        case .useOpaqueChromeSurfaces:
            return "Replaces translucent native materials with solid theme surfaces."
        case .deactivateInactiveTabsSooner:
            return "Caps hidden-tab deactivation delay at one hour to reduce background page work."
        }
    }

    static let defaultSelection = Set(allCases)
}

enum SumiEnergySaverThermalState: Int, Comparable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(_ thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .serious
        }
    }
}

struct SumiEnergySaverSystemSnapshot: Equatable, Sendable {
    var batteryPercentage: Int?
    var isUsingBatteryPower: Bool
    var isLowPowerModeEnabled: Bool
    var thermalState: SumiEnergySaverThermalState

    static func current(processInfo: ProcessInfo = .processInfo) -> Self {
        let powerSource = SumiPowerSourceSnapshot.current()
        return Self(
            batteryPercentage: powerSource.batteryPercentage,
            isUsingBatteryPower: powerSource.isUsingBatteryPower,
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            thermalState: SumiEnergySaverThermalState(processInfo.thermalState)
        )
    }
}

struct SumiEnergySaverActivation: Equatable, Sendable {
    enum Reason: Hashable, Sendable {
        case forcedOn
        case lowBattery
        case systemLowPowerMode
        case thermalPressure
    }

    let isActive: Bool
    let reasons: Set<Reason>

    var statusText: String {
        guard isActive else { return "Inactive" }
        if reasons.contains(.forcedOn) {
            return "Active: enabled manually"
        }

        var details: [String] = []
        if reasons.contains(.systemLowPowerMode) {
            details.append("macOS Low Power Mode")
        }
        if reasons.contains(.lowBattery) {
            details.append("battery threshold")
        }
        if reasons.contains(.thermalPressure) {
            details.append("thermal pressure")
        }
        return "Active: \(details.joined(separator: ", "))"
    }
}

enum SumiEnergySaverPolicy {
    static let defaultBatteryThreshold = 20
    static let minimumBatteryThreshold = 10
    static let maximumBatteryThreshold = 90
    static let batteryThresholdOptions = Array(stride(from: 10, through: 90, by: 10))
    static let maximumInactiveTabDeactivationDelay: TimeInterval = 60 * 60

    static func clampedBatteryThreshold(_ threshold: Int) -> Int {
        let bounded = min(max(threshold, minimumBatteryThreshold), maximumBatteryThreshold)
        return batteryThresholdOptions.min { lhs, rhs in
            let lhsDistance = abs(lhs - bounded)
            let rhsDistance = abs(rhs - bounded)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        } ?? defaultBatteryThreshold
    }

    static func activation(
        mode: SumiEnergySaverMode,
        batteryThreshold: Int,
        snapshot: SumiEnergySaverSystemSnapshot
    ) -> SumiEnergySaverActivation {
        switch mode {
        case .on:
            return SumiEnergySaverActivation(isActive: true, reasons: [.forcedOn])
        case .off:
            return SumiEnergySaverActivation(isActive: false, reasons: [])
        case .automatic:
            var reasons = Set<SumiEnergySaverActivation.Reason>()
            if snapshot.isLowPowerModeEnabled {
                reasons.insert(.systemLowPowerMode)
            }
            if snapshot.isUsingBatteryPower,
               let percentage = snapshot.batteryPercentage,
               percentage <= clampedBatteryThreshold(batteryThreshold) {
                reasons.insert(.lowBattery)
            }
            if snapshot.thermalState >= .serious {
                reasons.insert(.thermalPressure)
            }
            return SumiEnergySaverActivation(isActive: !reasons.isEmpty, reasons: reasons)
        }
    }
}

@MainActor
protocol SumiEnergySaverSystemMonitoring: AnyObject, Sendable {
    var snapshot: SumiEnergySaverSystemSnapshot { get }

    @discardableResult
    func addObserver(
        _ observer: @escaping @MainActor (SumiEnergySaverSystemSnapshot) -> Void
    ) -> UUID

    func removeObserver(_ token: UUID)
}

@MainActor
final class SumiEnergySaverSystemMonitor: SumiEnergySaverSystemMonitoring {
    static let shared = SumiEnergySaverSystemMonitor()

    private let processInfo: ProcessInfo
    private let notificationCenter: NotificationCenter
    private(set) var snapshot: SumiEnergySaverSystemSnapshot
    private var observers: [UUID: @MainActor (SumiEnergySaverSystemSnapshot) -> Void] = [:]
    private var notificationTokens: [NSObjectProtocol] = []
    private var powerSourcesRunLoopSource: CFRunLoopSource?

    init(
        processInfo: ProcessInfo = .processInfo,
        notificationCenter: NotificationCenter = .default
    ) {
        self.processInfo = processInfo
        self.notificationCenter = notificationCenter
        self.snapshot = .current(processInfo: processInfo)
    }

    @discardableResult
    func addObserver(
        _ observer: @escaping @MainActor (SumiEnergySaverSystemSnapshot) -> Void
    ) -> UUID {
        let token = UUID()
        observers[token] = observer
        startIfNeeded()
        observer(snapshot)
        return token
    }

    func removeObserver(_ token: UUID) {
        observers[token] = nil
        stopIfUnused()
    }

    private func startIfNeeded() {
        guard notificationTokens.isEmpty, powerSourcesRunLoopSource == nil else { return }

        notificationTokens = [
            notificationCenter.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: processInfo,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            },
            notificationCenter.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: processInfo,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            },
        ]

        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let monitor = Unmanaged<SumiEnergySaverSystemMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in
                    monitor.refresh()
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() else {
            return
        }

        powerSourcesRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func stopIfUnused() {
        guard observers.isEmpty else { return }

        for token in notificationTokens {
            notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()

        if let powerSourcesRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourcesRunLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSourcesRunLoopSource)
            self.powerSourcesRunLoopSource = nil
        }
    }

    private func refresh() {
        let updatedSnapshot = SumiEnergySaverSystemSnapshot.current(processInfo: processInfo)
        guard updatedSnapshot != snapshot else { return }
        snapshot = updatedSnapshot
        for observer in observers.values {
            observer(updatedSnapshot)
        }
    }
}

private struct SumiPowerSourceSnapshot {
    let batteryPercentage: Int?
    let isUsingBatteryPower: Bool

    static func current() -> Self {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return Self(batteryPercentage: nil, isUsingBatteryPower: false)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }

            let currentCapacity = description[kIOPSCurrentCapacityKey] as? NSNumber
            let maximumCapacity = description[kIOPSMaxCapacityKey] as? NSNumber
            let percentage: Int?
            if let currentCapacity, let maximumCapacity, maximumCapacity.doubleValue > 0 {
                percentage = Int(
                    (currentCapacity.doubleValue / maximumCapacity.doubleValue * 100).rounded()
                )
            } else {
                percentage = nil
            }

            return Self(
                batteryPercentage: percentage,
                isUsingBatteryPower:
                    description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            )
        }

        return Self(batteryPercentage: nil, isUsingBatteryPower: false)
    }
}
