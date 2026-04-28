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

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Memory Saver",
                subtitle: "Choose one inactive-tab policy. Pinned tabs and Essentials keep their launcher identity."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                        memoryModeRow(
                            descriptor,
                            settings: settings,
                            isSelected: descriptor.mode == settings.memoryMode
                        )
                    }
                }

                Text(SumiMemoryModeSettingsDescriptor.launcherPreservationCopy)
                    .font(.caption)
                    .foregroundStyle(tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func memoryModeRow(
        _ descriptor: SumiMemoryModeSettingsDescriptor,
        settings: SumiSettingsService,
        isSelected: Bool
    ) -> some View {
        Button {
            settings.memoryMode = descriptor.mode
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : tokens.secondaryText)
                        .frame(width: 18, height: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(descriptor.title)
                            .font(.headline)
                            .foregroundStyle(isSelected ? Color.accentColor : tokens.primaryText)
                        Text(descriptor.detail)
                            .font(.caption)
                            .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if settings.memoryMode == .custom && descriptor.mode == .custom {
                    customDelayControl(settings: settings)
                        .padding(.leading, 28)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : tokens.separator.opacity(0.45),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .font(.caption)
                .foregroundStyle(tokens.secondaryText)
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
