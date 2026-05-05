//
//  Appearance.swift
//  Sumi
//

import SwiftUI

struct SettingsAppearanceTab: View {
    @Environment(\.sumiSettings) var sumiSettings

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Sidebar",
                subtitle: "Controls that affect browser chrome and sidebar layout."
            ) {
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
                    .frame(width: 120)
                }

                SettingsRow(
                    title: "Compact spaces",
                    subtitle: "Use denser space presentation in the sidebar."
                ) {
                    Toggle("", isOn: $settings.sidebarCompactSpaces)
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
                    .frame(width: 150)
                    .disabled(!settings.showNewTabButtonInTabList)
                }
            }
        }
    }
}
