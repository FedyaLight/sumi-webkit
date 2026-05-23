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
        detail: "Deactivates inactive tabs sooner. Frees memory faster, but tabs may reload more often."
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

    static let launcherPreservationCopy =
        "Deactivated tabs remain visible. Pinned tabs and Essentials remain launchers; Memory Saver can deactivate their hidden live runtime without removing launcher identity."
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
                Picker("Mode", selection: $settings.memoryMode) {
                    ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                        Text(descriptor.title).tag(descriptor.mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if let selectedDescriptor {
                    Text(selectedDescriptor.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if settings.memoryMode == .custom {
                    SettingsDivider()
                    customDelayControl(settings: settings)
                }

                Text(SumiMemoryModeSettingsDescriptor.launcherPreservationCopy)
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
        let delayHours = Binding<Double>(
            get: {
                settings.memorySaverCustomDeactivationDelay / 3600
            },
            set: { newValue in
                settings.memorySaverCustomDeactivationDelay = newValue * 3600
            }
        )

        return SettingsRow(
            title: "Deactivate inactive tabs after",
            subtitle: nil
        ) {
            Stepper(value: delayHours, in: 0.25...24, step: 0.25) {
                Text(formattedDelay(settings.memorySaverCustomDeactivationDelay))
                    .monospacedDigit()
            }
            .frame(maxWidth: 180)
        }
    }

    private func formattedDelay(_ delay: TimeInterval) -> String {
        let minutes = Int((SumiMemorySaverCustomDelay.clamped(delay) / 60).rounded())
        if minutes < 60 {
            return "\(minutes) minutes"
        }

        let hours = Double(minutes) / 60
        if hours.rounded() == hours {
            return "\(Int(hours)) hours"
        }
        return "\(hours.formatted(.number.precision(.fractionLength(2)))) hours"
    }
}
