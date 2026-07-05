//
//  Appearance.swift
//  Sumi
//

import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.sumiBoostsModule) private var boostsModule
    @State private var cachedBoostsModuleEnabled: Bool?

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Browser",
                subtitle: "Controls that affect browser chrome, Boosts, and sidebar layout."
            ) {
                SettingsRow(
                    title: "Boosts",
                    subtitle: "Show Boost controls and apply active Boost styles to web pages."
                ) {
                    Toggle("", isOn: boostsModuleEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Sidebar toggle button",
                    subtitle: "Expose the sidebar visibility control in browser chrome."
                ) {
                    Toggle("", isOn: $settings.showSidebarToggleButton)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Sidebar side",
                    subtitle: "Place the browser sidebar on the left or right edge."
                ) {
                    Picker("", selection: $settings.sidebarPosition) {
                        ForEach(SidebarPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .labelsHidden()
                    .settingsTrailingControl(width: 120)
                }

                SettingsRow(
                    title: "Mini player",
                    subtitle: "Show media controls for background tabs at the bottom of the sidebar."
                ) {
                    Toggle("", isOn: $settings.sidebarMiniPlayerEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Frameless chrome",
                    subtitle: "Extend web content to the side and bottom window edges, keeping the top bar and sidebar."
                ) {
                    Toggle("", isOn: $settings.framelessChrome)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Preview link URL",
                    subtitle: "Show the hovered link target in the status area."
                ) {
                    Toggle("", isOn: $settings.showLinkStatusBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Browser notifications",
                    subtitle: "Show brief feedback banners for actions like copying URLs, switching profiles, and closing tabs."
                ) {
                    Toggle("", isOn: $settings.showBrowserToasts)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "New Tab button",
                    subtitle: "Show a New Tab control in the tab list."
                ) {
                    Toggle("", isOn: $settings.showNewTabButtonInTabList)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "New Tab button position",
                    subtitle: "Choose where the tab-list button appears."
                ) {
                    Picker("", selection: $settings.tabListNewTabButtonPosition) {
                        ForEach(TabListNewTabButtonPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .labelsHidden()
                    .settingsTrailingControl(width: 150)
                    .disabled(!settings.showNewTabButtonInTabList)
                }
            }
        }
        .onAppear {
            cachedBoostsModuleEnabled = boostsModule.isEnabled
        }
    }

    private var boostsModuleEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                cachedBoostsModuleEnabled ?? boostsModule.isEnabled
            },
            set: { isEnabled in
                boostsModule.setEnabled(isEnabled)
                cachedBoostsModuleEnabled = isEnabled
            }
        )
    }
}
