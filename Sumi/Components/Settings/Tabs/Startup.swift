//
//  Startup.swift
//  Sumi
//

import SumiDomain
import SwiftUI

struct SettingsStartupTab: View {
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        @Bindable var settings = sumiSettings

        SettingsSection(title: "On Startup") {
            SettingsRow(
                title: "Open",
                subtitle: settings.startupMode.subtitle,
                systemImage: "power"
            ) {
                Picker("", selection: $settings.startupMode) {
                    ForEach(SumiStartupMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .settingsMenuPicker(width: 210)
            }

            if settings.startupMode == .specificPage {
                SettingsDivider()

                SettingsRow(
                    title: "Page URL",
                    subtitle: SumiStartupPageURL.validationMessage(
                        for: settings.startupPageURLString
                    ),
                    systemImage: "link"
                ) {
                    TextField("https://example.com", text: $settings.startupPageURLString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
            }
        }
    }
}
