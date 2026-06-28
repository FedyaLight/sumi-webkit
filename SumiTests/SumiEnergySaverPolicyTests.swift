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

    func testBatteryThresholdUsesFixedMenuOptions() {
        XCTAssertEqual(
            SumiEnergySaverPolicy.batteryThresholdOptions,
            [10, 20, 30, 40, 50, 60, 70, 80, 90]
        )
        XCTAssertEqual(SumiEnergySaverPolicy.clampedBatteryThreshold(7), 10)
        XCTAssertEqual(SumiEnergySaverPolicy.clampedBatteryThreshold(27), 30)
        XCTAssertEqual(SumiEnergySaverPolicy.clampedBatteryThreshold(105), 90)
    }

    func testSettingsOrderKeepsManualChoicesBeforeAutomatic() {
        XCTAssertEqual(SumiEnergySaverMode.settingsOrder, [.off, .on, .automatic])
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

    func testProactiveTimerSchedulerDoesNotStartTaskWithoutTimers() {
        var didFire = false
        let scheduler = ProactiveTabSuspensionTimerScheduler(
            suspensionClock: TabSuspensionTimerSchedulerClock(liveUptime: 100),
            timerSleep: { _ in
                XCTFail("Scheduler should not sleep without a timer deadline")
            },
            handleDueTimers: {
                didFire = true
            }
        )

        scheduler.schedule { _ in nil }

        XCTAssertEqual(scheduler.activeTimerCount, 0)
        XCTAssertFalse(scheduler.hasScheduledTaskForTesting)
        XCTAssertTrue(scheduler.isIdle)
        XCTAssertFalse(didFire)
    }

    func testProactiveTimerSchedulerUsesEarliestDeadlineAndCancelsWhenEmpty() {
        let firstTabID = UUID()
        let secondTabID = UUID()
        let hiddenStarts = [
            firstTabID: TimeInterval(10),
            secondTabID: TimeInterval(20),
        ]
        let scheduler = ProactiveTabSuspensionTimerScheduler(
            suspensionClock: TabSuspensionTimerSchedulerClock(liveUptime: 15),
            timerSleep: { _ in
                try await Task.sleep(nanoseconds: 1_000_000_000)
            },
            handleDueTimers: { /* no-op */ }
        )

        scheduler.armTimer(
            for: firstTabID,
            requestedDelay: 30,
            hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
        )
        XCTAssertEqual(scheduler.scheduledDeadlineLiveUptimeForTesting, 40)
        XCTAssertTrue(scheduler.hasScheduledTaskForTesting)

        scheduler.armTimer(
            for: secondTabID,
            requestedDelay: 5,
            hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
        )
        XCTAssertEqual(scheduler.scheduledDeadlineLiveUptimeForTesting, 25)
        XCTAssertEqual(scheduler.activeTimerCount, 2)

        XCTAssertTrue(
            scheduler.cancelTimer(
                for: secondTabID,
                hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
            )
        )
        XCTAssertEqual(scheduler.scheduledDeadlineLiveUptimeForTesting, 40)
        XCTAssertTrue(scheduler.hasScheduledTaskForTesting)

        XCTAssertTrue(
            scheduler.cancelTimer(
                for: firstTabID,
                hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
            )
        )
        XCTAssertEqual(scheduler.activeTimerCount, 0)
        XCTAssertFalse(scheduler.hasScheduledTaskForTesting)
        XCTAssertTrue(scheduler.isIdle)
    }

    func testProactiveTimerSchedulerDueTimersRemoveOrphanedHiddenState() {
        let dueTabID = UUID()
        let orphanedTabID = UUID()
        let futureTabID = UUID()
        var hiddenStarts: [UUID: TimeInterval] = [
            dueTabID: 10,
            orphanedTabID: 10,
            futureTabID: 19,
        ]
        let scheduler = ProactiveTabSuspensionTimerScheduler(
            suspensionClock: TabSuspensionTimerSchedulerClock(liveUptime: 20),
            timerSleep: { _ in
                try await Task.sleep(nanoseconds: 1_000_000_000)
            },
            handleDueTimers: { /* no-op */ }
        )

        scheduler.armTimer(
            for: dueTabID,
            requestedDelay: 10,
            hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
        )
        scheduler.armTimer(
            for: orphanedTabID,
            requestedDelay: 10,
            hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
        )
        scheduler.armTimer(
            for: futureTabID,
            requestedDelay: 10,
            hiddenStartedAtLiveUptime: { hiddenStarts[$0] }
        )

        hiddenStarts.removeValue(forKey: orphanedTabID)
        let dueTimers = scheduler.dueTimers {
            hiddenStarts[$0]
        }

        XCTAssertEqual(dueTimers.map(\.tabID), [dueTabID])
        XCTAssertTrue(scheduler.containsTimer(for: dueTabID))
        XCTAssertFalse(scheduler.containsTimer(for: orphanedTabID))
        XCTAssertTrue(scheduler.containsTimer(for: futureTabID))
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

private struct TabSuspensionTimerSchedulerClock: SumiSuspensionClock {
    let liveUptime: TimeInterval
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
