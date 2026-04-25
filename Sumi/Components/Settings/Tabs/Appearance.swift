//
//  Appearance.swift
//  Sumi
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @EnvironmentObject private var browserManager: BrowserManager

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        @Bindable var settings = sumiSettings

        Form {
            Picker(
                "Window Scheme",
                selection: $settings.windowSchemeMode
            ) {
                ForEach(WindowSchemeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Section("Sumi Theme") {
                Toggle("Use System Colors", isOn: $settings.themeUseSystemColors)

                Picker("Dark Theme Style", selection: $settings.darkThemeStyle) {
                    ForEach(DarkThemeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Toggle("Styled Status Panel", isOn: $settings.themeStyledStatusPanel)

                Picker("Border Radius", selection: $settings.themeBorderRadius) {
                    Text("System").tag(-1)
                    Text("6 px").tag(6)
                    Text("8 px").tag(8)
                    Text("10 px").tag(10)
                    Text("12 px").tag(12)
                    Text("14 px").tag(14)
                }
            }

            Section("Space Theme") {
                if let currentSpace = browserManager.tabManager.currentSpace {
                    HStack {
                        Text("Current Space")
                        Spacer()
                        Text(currentSpace.name)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Edit Current Workspace Theme...") {
                    browserManager.showGradientEditor()
                }
                .disabled(browserManager.tabManager.currentSpace == nil)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.windowBackground)
    }
}
