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

    static let lightweight = SumiMemoryModeSettingsDescriptor(
        mode: .lightweight,
        title: "Lightweight",
        detail: "Uses the smallest live WebView footprint. Later prompts may unload hidden eligible WebView instances more aggressively to reduce memory usage."
    )

    static let balanced = SumiMemoryModeSettingsDescriptor(
        mode: .balanced,
        title: "Balanced",
        detail: "Recommended default. Later prompts keep the selected tab and a small recent live set warm, then suspend hidden inactive tabs after a timeout."
    )

    static let performance = SumiMemoryModeSettingsDescriptor(
        mode: .performance,
        title: "Performance",
        detail: "Keeps more tabs warm in future prompts and may use more memory to reduce WebView recreation and reloads."
    )

    static let all: [SumiMemoryModeSettingsDescriptor] = [
        .lightweight,
        .balanced,
        .performance,
    ]

    static let launcherPreservationCopy =
        "Suspended tabs remain visible. Pinned tabs and Essentials remain launchers. This setting does not remove Essentials or convert them into normal tabs."
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
            Section("Memory Mode") {
                Picker("Memory Mode", selection: $settings.memoryMode) {
                    ForEach(SumiMemoryModeSettingsDescriptor.all) { descriptor in
                        Text(descriptor.title).tag(descriptor.mode)
                    }
                }
                .pickerStyle(.radioGroup)

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
}
