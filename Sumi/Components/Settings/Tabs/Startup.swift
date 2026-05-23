//
//  Startup.swift
//  Sumi
//

import SwiftUI

struct SettingsStartupTab: View {
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "On Startup",
                subtitle: "Choose what Sumi opens when the app starts."
            ) {
                Picker("Open", selection: $settings.startupMode) {
                    ForEach(SumiStartupMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.startupMode.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.startupMode == .specificPage {
                SettingsSection(
                    title: "Startup Page",
                    subtitle: "Used when startup is set to open a specific page."
                ) {
                    SettingsRow(
                        title: "Page URL",
                        subtitle: "Use a full URL or a bare domain."
                    ) {
                        TextField("https://example.com", text: $settings.startupPageURLString)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }

                    if let message = SumiStartupPageURL.validationMessage(for: settings.startupPageURLString) {
                        SettingsDivider()

                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
