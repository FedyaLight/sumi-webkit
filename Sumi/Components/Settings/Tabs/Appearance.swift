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

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Browser") {
                SettingsRow(
                    title: "Boosts",
                    subtitle: "Apply custom styles and page adjustments from Boosts.",
                    systemImage: "wand.and.stars"
                ) {
                    Toggle("", isOn: boostsModuleEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(boostsModule == nil)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Sidebar side",
                    systemImage: "rectangle.split.2x1"
                ) {
                    Picker("", selection: $settings.sidebarPosition) {
                        ForEach(SidebarPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .settingsMenuPicker(width: 120)
                }

                SettingsRow(
                    title: "Mini player",
                    subtitle: "Show media controls for background tabs in the sidebar.",
                    systemImage: "play.rectangle"
                ) {
                    Toggle("", isOn: $settings.sidebarMiniPlayerEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Frameless chrome",
                    subtitle: "Extend web content to the side and bottom edges of the window.",
                    systemImage: "rectangle.inset.filled"
                ) {
                    Toggle("", isOn: $settings.framelessChrome)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Preview link URL",
                    systemImage: "link"
                ) {
                    Toggle("", isOn: $settings.showLinkStatusBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Browser notifications",
                    subtitle: "Show brief in-app confirmation banners for browser actions.",
                    systemImage: "bell"
                ) {
                    Toggle("", isOn: $settings.showInAppNotifications)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "New Tab button",
                    systemImage: "plus"
                ) {
                    Toggle("", isOn: $settings.showNewTabButtonInTabList)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "New Tab button position",
                    systemImage: "arrow.up.and.down"
                ) {
                    Picker("", selection: $settings.tabListNewTabButtonPosition) {
                        ForEach(TabListNewTabButtonPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .settingsMenuPicker(width: 150)
                    .disabled(!settings.showNewTabButtonInTabList)
                }
            }
        }
        .onAppear {
            cachedBoostsModuleEnabled = boostsModule?.isEnabled
        }
    }

    private var boostsModuleEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                cachedBoostsModuleEnabled ?? boostsModule?.isEnabled ?? false
            },
            set: { isEnabled in
                guard let boostsModule else { return }
                boostsModule.setEnabled(isEnabled)
                cachedBoostsModuleEnabled = isEnabled
            }
        )
    }
}
