import XCTest

@testable import Sumi

@MainActor
final class SumiEnergySaverPolicyTests: XCTestCase {
    func testAutomaticModeUsesBatteryThresholdOnlyWhileDischarging() {
        let drainingBattery = snapshot(batteryPercentage: 20, isUsingBatteryPower: true)
        let connectedToPower = snapshot(batteryPercentage: 10, isUsingBatteryPower: false)

        XCTAssertEqual(
            activation(snapshot: drainingBattery),
            SumiEnergySaverActivation(isActive: true, reasons: [.lowBattery])
        )
        XCTAssertEqual(
            activation(snapshot: connectedToPower),
            SumiEnergySaverActivation(isActive: false, reasons: [])
        )
    }

    func testAutomaticModeRespondsToSystemLowPowerModeAndThermalPressure() {
        XCTAssertEqual(
            activation(snapshot: snapshot(isLowPowerModeEnabled: true)),
            SumiEnergySaverActivation(isActive: true, reasons: [.systemLowPowerMode])
        )
        XCTAssertEqual(
            activation(snapshot: snapshot(thermalState: .serious)),
            SumiEnergySaverActivation(isActive: true, reasons: [.thermalPressure])
        )
    }

    func testForcedModesOverrideAdaptiveSignals() {
        let stressedSnapshot = snapshot(
            batteryPercentage: 5,
            isUsingBatteryPower: true,
            isLowPowerModeEnabled: true,
            thermalState: .critical
        )

        XCTAssertEqual(
            activation(mode: .off, snapshot: stressedSnapshot),
            SumiEnergySaverActivation(isActive: false, reasons: [])
        )
        XCTAssertEqual(
            activation(mode: .on, snapshot: snapshot()),
            SumiEnergySaverActivation(isActive: true, reasons: [.forcedOn])
        )
    }

    func testSettingsPersistFeatureSelectionAndReactToMonitorUpdates() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let monitor = EnergySaverSystemMonitorProbe(snapshot: snapshot())
        let settings = SumiSettingsService(
            userDefaults: harness.defaults,
            energySaverSystemMonitor: monitor
        )

        XCTAssertEqual(settings.energySaverMode, .automatic)
        XCTAssertEqual(settings.energySaverBatteryThreshold, 20)
        XCTAssertEqual(settings.energySaverFeatures, Set(SumiEnergySaverFeature.allCases))
        XCTAssertFalse(settings.shouldReduceChromeMotion)

        settings.energySaverBatteryThreshold = 30
        settings.energySaverFeatures = [.reduceInterfaceAnimations]
        monitor.update(snapshot: snapshot(batteryPercentage: 25, isUsingBatteryPower: true))

        XCTAssertTrue(settings.shouldReduceChromeMotion)
        XCTAssertFalse(settings.shouldUseOpaqueChromeSurfaces)

        let recreatedSettings = SumiSettingsService(
            userDefaults: harness.defaults,
            energySaverSystemMonitor: monitor
        )
        XCTAssertEqual(recreatedSettings.energySaverBatteryThreshold, 30)
        XCTAssertEqual(recreatedSettings.energySaverFeatures, [.reduceInterfaceAnimations])
    }

    func testEnergySaverCapsInactiveTabDeactivationDelayAtOneHour() {
        XCTAssertEqual(
            TabSuspensionPolicy(memoryMode: .balanced, energySaverActive: true)
                .proactiveDeactivationDelay,
            60 * 60
        )
        XCTAssertEqual(
            TabSuspensionPolicy(
                memoryMode: .custom,
                customDeactivationDelay: 20 * 60,
                energySaverActive: true
            )
            .proactiveDeactivationDelay,
            20 * 60
        )
    }

    private func activation(
        mode: SumiEnergySaverMode = .automatic,
        snapshot: SumiEnergySaverSystemSnapshot
    ) -> SumiEnergySaverActivation {
        SumiEnergySaverPolicy.activation(
            mode: mode,
            batteryThreshold: 20,
            snapshot: snapshot
        )
    }

    private func snapshot(
        batteryPercentage: Int? = nil,
        isUsingBatteryPower: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        thermalState: SumiEnergySaverThermalState = .nominal
    ) -> SumiEnergySaverSystemSnapshot {
        SumiEnergySaverSystemSnapshot(
            batteryPercentage: batteryPercentage,
            isUsingBatteryPower: isUsingBatteryPower,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            thermalState: thermalState
        )
    }
}

@MainActor
private final class EnergySaverSystemMonitorProbe: SumiEnergySaverSystemMonitoring {
    private(set) var snapshot: SumiEnergySaverSystemSnapshot
    private var observers: [UUID: @MainActor (SumiEnergySaverSystemSnapshot) -> Void] = [:]

    init(snapshot: SumiEnergySaverSystemSnapshot) {
        self.snapshot = snapshot
    }

    @discardableResult
    func addObserver(
        _ observer: @escaping @MainActor (SumiEnergySaverSystemSnapshot) -> Void
    ) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(snapshot)
        return token
    }

    func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    func update(snapshot: SumiEnergySaverSystemSnapshot) {
        self.snapshot = snapshot
        for observer in observers.values {
            observer(snapshot)
        }
    }
}
