//
//  Appearance.swift
//  Sumi
//

import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @EnvironmentObject private var browserManager: BrowserManager

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Window Appearance",
                subtitle: "Choose how Sumi resolves light and dark surfaces."
            ) {
                SettingsRow(
                    title: "Window scheme",
                    subtitle: "Follow the system or force a light or dark browser window."
                ) {
                    Picker("", selection: $settings.windowSchemeMode) {
                        ForEach(WindowSchemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            SettingsSection(
                title: "Sumi Theme",
                subtitle: "Tune Sumi's browser chrome while preserving system-adaptive colors."
            ) {
                SettingsRow(
                    title: "Use system colors",
                    subtitle: "Let macOS drive the core chrome palette."
                ) {
                    Toggle("", isOn: $settings.themeUseSystemColors)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Dark theme style",
                    subtitle: "Controls the treatment used when Sumi renders dark chrome."
                ) {
                    Picker("", selection: $settings.darkThemeStyle) {
                        ForEach(DarkThemeStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                SettingsRow(
                    title: "Styled status panel",
                    subtitle: "Match link previews and status surfaces to the active theme."
                ) {
                    Toggle("", isOn: $settings.themeStyledStatusPanel)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Corner radius",
                    subtitle: "Use the system default or a fixed chrome radius."
                ) {
                    Picker("", selection: $settings.themeBorderRadius) {
                        Text("System").tag(-1)
                        Text("6 px").tag(6)
                        Text("8 px").tag(8)
                        Text("10 px").tag(10)
                        Text("12 px").tag(12)
                        Text("14 px").tag(14)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }

            SettingsSection(
                title: "Space Theme",
                subtitle: "Edit the active workspace theme without leaving Settings."
            ) {
                if let currentSpace = browserManager.tabManager.currentSpace {
                    SettingsStatusRow(
                        title: "Current space",
                        value: currentSpace.name,
                        systemImage: "rectangle.3.group"
                    )
                } else {
                    SettingsStatusRow(
                        title: "Current space",
                        value: "No space selected",
                        systemImage: "rectangle.3.group"
                    )
                }

                SettingsActionRow(
                    title: "Workspace theme",
                    subtitle: "Open the gradient and color editor for the selected space.",
                    systemImage: "paintpalette",
                    buttonTitle: "Edit Theme..."
                ) {
                    browserManager.showGradientEditor()
                }
                .disabled(browserManager.tabManager.currentSpace == nil)
            }
        }
    }
}
