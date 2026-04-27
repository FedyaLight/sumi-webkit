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
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        @Bindable var settings = sumiSettings

        Form {
            Section("Memory Saver") {
                Picker("Memory Saver", selection: $settings.memoryMode) {
                    ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                        Text(descriptor.title).tag(descriptor.mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.memoryMode == .custom {
                    customDelayControl(settings: settings)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                        memoryModeDescriptionRow(
                            descriptor,
                            isSelected: descriptor.mode == settings.memoryMode
                        )
                    }
                }
                .padding(.top, 4)

                Text(SumiMemoryModeSettingsDescriptor.launcherPreservationCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.windowBackground)
    }

    private func memoryModeDescriptionRow(
        _ descriptor: SumiMemoryModeSettingsDescriptor,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.title)
                    .font(.headline)
                Text(descriptor.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

        return HStack(spacing: 12) {
            Text("Deactivate inactive tabs after:")
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
