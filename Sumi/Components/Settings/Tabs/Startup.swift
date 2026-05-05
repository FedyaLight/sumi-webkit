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
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SumiStartupMode.allCases) { mode in
                        startupModeRow(mode, selection: $settings.startupMode)
                    }
                }
            }

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
                        .disabled(settings.startupMode != .specificPage)
                }

                if settings.startupMode == .specificPage,
                   let message = SumiStartupPageURL.validationMessage(for: settings.startupPageURLString)
                {
                    SettingsDivider()

                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startupModeRow(
        _ mode: SumiStartupMode,
        selection: Binding<SumiStartupMode>
    ) -> some View {
        Button {
            selection.wrappedValue = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selection.wrappedValue == mode ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(selection.wrappedValue == mode ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.body)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
