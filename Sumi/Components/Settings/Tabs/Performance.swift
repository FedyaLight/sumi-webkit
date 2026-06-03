//
//  Performance.swift
//  Sumi
//

import SwiftUI

struct SumiMemoryModeSettingsDescriptor: Identifiable, Equatable {
    let mode: SumiMemoryMode
    let title: String
    let detail: String

    var id: SumiMemoryMode { mode }

    var segmentedTitle: String {
        switch mode {
        case .custom:
            return "Custom"
        default:
            return title
        }
    }

    static let moderate = SumiMemoryModeSettingsDescriptor(
        mode: .moderate,
        title: "Moderate",
        detail: "Deactivates inactive tabs after a longer period. Fewer reloads."
    )

    static let balanced = SumiMemoryModeSettingsDescriptor(
        mode: .balanced,
        title: "Balanced",
        detail: "Recommended. Balances memory savings and convenience."
    )

    static let maximum = SumiMemoryModeSettingsDescriptor(
        mode: .maximum,
        title: "Maximum",
        detail: "Deactivates inactive tabs sooner."
    )

    static let custom = SumiMemoryModeSettingsDescriptor(
        mode: .custom,
        title: "Custom Deactivation Delay",
        detail: "Choose when inactive tabs are deactivated."
    )

    static let all: [SumiMemoryModeSettingsDescriptor] = [
        .moderate,
        .balanced,
        .maximum,
        .custom,
    ]
}

struct SettingsPerformanceTab: View {
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Memory Saver",
                subtitle: "Choose one inactive-tab policy. Pinned tabs and Essentials keep their launcher identity."
            ) {
                SettingsRow(
                    title: "Mode",
                    subtitle: selectedDescriptor?.detail
                ) {
                    Picker("Mode", selection: $settings.memoryMode) {
                        ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                            Text(descriptor.segmentedTitle).tag(descriptor.mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .settingsTrailingControl(width: 340)
                }

                if settings.memoryMode == .custom {
                    SettingsDivider()
                    customDelayControl(settings: settings)
                }
            }

            SettingsSection(
                title: "Energy Saver",
                subtitle: "Reduce native browser chrome work without modifying website content."
            ) {
                SettingsRow(
                    title: "Mode",
                    subtitle: energySaverStatusText
                ) {
                    Picker("Mode", selection: $settings.energySaverMode) {
                        ForEach(SumiEnergySaverMode.settingsOrder) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .settingsTrailingControl(width: 230)
                }

                if settings.energySaverMode == .automatic {
                    SettingsDivider()
                    SettingsRow(
                        title: "Use on battery at or below",
                        subtitle: "Automatic mode also follows macOS Low Power Mode and serious thermal pressure."
                    ) {
                        Picker(
                            "Use on battery at or below",
                            selection: $settings.energySaverBatteryThreshold
                        ) {
                            ForEach(SumiEnergySaverPolicy.batteryThresholdOptions, id: \.self) { threshold in
                                Text("\(threshold)%").tag(threshold)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .settingsTrailingControl(width: 120)
                    }
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("While Energy Saver is active")
                        .font(.callout.weight(.semibold))

                    ForEach(SumiEnergySaverFeature.allCases) { feature in
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                Text(feature.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 16)

                            Toggle("", isOn: energySaverFeatureBinding(feature, settings: settings))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }

                Text("macOS Reduce Motion is always honored independently, including when Energy Saver is Off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedDescriptor: SumiMemoryModeSettingsDescriptor? {
        SumiMemoryModeSettingsDescriptor.all.first { $0.mode == sumiSettings.memoryMode }
    }

    private func customDelayControl(settings: SumiSettingsService) -> some View {
        let delaySelection = Binding<TimeInterval>(
            get: {
                SumiMemorySaverCustomDelay.nearestPreset(to: settings.memorySaverCustomDeactivationDelay)
            },
            set: { newValue in
                settings.memorySaverCustomDeactivationDelay = newValue
            }
        )

        return SettingsRow(
            title: "Deactivate inactive tabs after:",
            subtitle: nil
        ) {
            Picker("Deactivate inactive tabs after", selection: delaySelection) {
                ForEach(SumiMemorySaverCustomDelay.presetOptions, id: \.self) { delay in
                    Text(formattedDelay(delay)).tag(delay)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .settingsTrailingControl(width: 140)
        }
    }

    private func formattedDelay(_ delay: TimeInterval) -> String {
        let minutes = Int((SumiMemorySaverCustomDelay.clamped(delay) / 60).rounded())
        if minutes < 60 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }

        let hours = Double(minutes) / 60
        if hours.rounded() == hours {
            let wholeHours = Int(hours)
            return wholeHours == 1 ? "1 hour" : "\(wholeHours) hours"
        }
        return "\(hours.formatted(.number.precision(.fractionLength(2)))) hours"
    }

    private var energySaverStatusText: String {
        let snapshot = sumiSettings.energySaverSystemSnapshot
        let batteryText: String
        if let percentage = snapshot.batteryPercentage {
            batteryText = snapshot.isUsingBatteryPower
                ? "Battery \(percentage)%"
                : "Battery \(percentage)%, connected to power"
        } else {
            batteryText = "No internal battery"
        }
        return "\(sumiSettings.energySaverActivation.statusText). \(batteryText)."
    }

    private func energySaverFeatureBinding(
        _ feature: SumiEnergySaverFeature,
        settings: SumiSettingsService
    ) -> Binding<Bool> {
        Binding(
            get: {
                settings.energySaverFeatures.contains(feature)
            },
            set: { isEnabled in
                if isEnabled {
                    settings.energySaverFeatures.insert(feature)
                } else {
                    settings.energySaverFeatures.remove(feature)
                }
            }
        )
    }
}
