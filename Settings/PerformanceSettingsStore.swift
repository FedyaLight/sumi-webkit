//
//  PerformanceSettingsStore.swift
//  Sumi
//

import Foundation

@MainActor
@Observable
final class PerformanceSettingsStore {
    private let userDefaults: UserDefaults
    private let tabUnloadTimeoutKey: String
    private let memoryModeKey: String
    private let memorySaverCustomDeactivationDelayKey: String
    private let energySaverModeKey: String
    private let energySaverBatteryThresholdKey: String
    private let energySaverFeaturesKey: String

    private let energySaverSystemMonitor: any SumiEnergySaverSystemMonitoring
    @ObservationIgnored
    nonisolated(unsafe) private var energySaverSystemObservationToken: UUID?

    var tabUnloadTimeout: TimeInterval {
        didSet {
            Persisted.double(tabUnloadTimeout, key: tabUnloadTimeoutKey, defaults: userDefaults)
            NotificationCenter.default.post(
                name: .tabUnloadTimeoutChanged,
                object: nil,
                userInfo: ["timeout": tabUnloadTimeout]
            )
        }
    }

    var memoryMode: SumiMemoryMode {
        didSet {
            Persisted.rawRepresentable(memoryMode, key: memoryModeKey, defaults: userDefaults)
            NotificationCenter.default.post(name: .sumiMemorySaverPolicyChanged, object: nil)
        }
    }

    var memorySaverCustomDeactivationDelay: TimeInterval {
        didSet {
            let normalized = SumiMemorySaverCustomDelay.nearestPreset(
                to: memorySaverCustomDeactivationDelay
            )
            if normalized != memorySaverCustomDeactivationDelay {
                memorySaverCustomDeactivationDelay = normalized
                return
            }
            Persisted.double(
                memorySaverCustomDeactivationDelay,
                key: memorySaverCustomDeactivationDelayKey,
                defaults: userDefaults
            )
            NotificationCenter.default.post(name: .sumiMemorySaverPolicyChanged, object: nil)
        }
    }

    var energySaverMode: SumiEnergySaverMode {
        didSet {
            Persisted.rawRepresentable(energySaverMode, key: energySaverModeKey, defaults: userDefaults)
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverBatteryThreshold: Int {
        didSet {
            let clamped = SumiEnergySaverPolicy.clampedBatteryThreshold(energySaverBatteryThreshold)
            if clamped != energySaverBatteryThreshold {
                energySaverBatteryThreshold = clamped
                return
            }
            Persisted.int(
                energySaverBatteryThreshold,
                key: energySaverBatteryThresholdKey,
                defaults: userDefaults
            )
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverFeatures: Set<SumiEnergySaverFeature> {
        didSet {
            Persisted.stringArray(
                energySaverFeatures.map(\.rawValue).sorted(),
                key: energySaverFeaturesKey,
                defaults: userDefaults
            )
            notifyEnergySaverPolicyChanged()
        }
    }

    private(set) var energySaverSystemSnapshot: SumiEnergySaverSystemSnapshot {
        didSet {
            guard energySaverSystemSnapshot != oldValue else { return }
            notifyEnergySaverPolicyChanged()
        }
    }

    var energySaverActivation: SumiEnergySaverActivation {
        SumiEnergySaverPolicy.activation(
            mode: energySaverMode,
            batteryThreshold: energySaverBatteryThreshold,
            snapshot: energySaverSystemSnapshot
        )
    }

    func energySaverApplies(_ feature: SumiEnergySaverFeature) -> Bool {
        energySaverActivation.isActive && energySaverFeatures.contains(feature)
    }

    var shouldReduceChromeMotion: Bool {
        energySaverApplies(.reduceInterfaceAnimations)
    }

    var shouldUseOpaqueChromeSurfaces: Bool {
        energySaverApplies(.useOpaqueChromeSurfaces)
    }

    init(
        userDefaults: UserDefaults,
        tabUnloadTimeoutKey: String,
        memoryModeKey: String,
        memorySaverCustomDeactivationDelayKey: String,
        energySaverModeKey: String,
        energySaverBatteryThresholdKey: String,
        energySaverFeaturesKey: String,
        energySaverSystemMonitor: any SumiEnergySaverSystemMonitoring
    ) {
        self.userDefaults = userDefaults
        self.tabUnloadTimeoutKey = tabUnloadTimeoutKey
        self.memoryModeKey = memoryModeKey
        self.memorySaverCustomDeactivationDelayKey = memorySaverCustomDeactivationDelayKey
        self.energySaverModeKey = energySaverModeKey
        self.energySaverBatteryThresholdKey = energySaverBatteryThresholdKey
        self.energySaverFeaturesKey = energySaverFeaturesKey
        self.energySaverSystemMonitor = energySaverSystemMonitor

        self.tabUnloadTimeout = userDefaults.double(forKey: tabUnloadTimeoutKey)

        let storedMemoryMode = userDefaults.string(forKey: memoryModeKey)
        let resolvedMemoryMode = SumiMemoryMode.persistedValue(storedMemoryMode)
        self.memoryMode = resolvedMemoryMode
        if storedMemoryMode != resolvedMemoryMode.rawValue {
            Persisted.rawRepresentable(resolvedMemoryMode, key: memoryModeKey, defaults: userDefaults)
        }

        let storedCustomDelay: TimeInterval? = userDefaults.object(
            forKey: memorySaverCustomDeactivationDelayKey
        ) == nil
            ? nil
            : userDefaults.double(forKey: memorySaverCustomDeactivationDelayKey)
        let resolvedCustomDelay = SumiMemorySaverCustomDelay.validatedOrDefault(storedCustomDelay)
        self.memorySaverCustomDeactivationDelay = resolvedCustomDelay
        if storedCustomDelay != resolvedCustomDelay {
            Persisted.double(
                resolvedCustomDelay,
                key: memorySaverCustomDeactivationDelayKey,
                defaults: userDefaults
            )
        }

        self.energySaverMode = SumiEnergySaverMode(
            rawValue: userDefaults.string(forKey: energySaverModeKey)
                ?? SumiEnergySaverMode.automatic.rawValue
        ) ?? .automatic
        let storedEnergySaverBatteryThreshold = userDefaults.integer(
            forKey: energySaverBatteryThresholdKey
        )
        let resolvedEnergySaverBatteryThreshold = SumiEnergySaverPolicy.clampedBatteryThreshold(
            storedEnergySaverBatteryThreshold
        )
        self.energySaverBatteryThreshold = resolvedEnergySaverBatteryThreshold
        if storedEnergySaverBatteryThreshold != resolvedEnergySaverBatteryThreshold {
            Persisted.int(
                resolvedEnergySaverBatteryThreshold,
                key: energySaverBatteryThresholdKey,
                defaults: userDefaults
            )
        }
        self.energySaverFeatures = Set(
            (userDefaults.stringArray(forKey: energySaverFeaturesKey) ?? [])
                .compactMap(SumiEnergySaverFeature.init(rawValue:))
        )
        self.energySaverSystemSnapshot = energySaverSystemMonitor.snapshot
        energySaverSystemObservationToken = energySaverSystemMonitor.addObserver {
            [weak self] snapshot in
            self?.energySaverSystemSnapshot = snapshot
        }
    }

    deinit {
        let monitor = energySaverSystemMonitor
        if let token = energySaverSystemObservationToken {
            Task { @MainActor in
                monitor.removeObserver(token)
            }
        }
    }

    private func notifyEnergySaverPolicyChanged() {
        // object is nil so observers stay tied to the settings façade, not this store.
        NotificationCenter.default.post(name: .sumiEnergySaverPolicyChanged, object: nil)
    }
}
