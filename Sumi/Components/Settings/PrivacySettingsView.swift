//
//  PrivacySettingsView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.sumiTrackingProtectionModule) private var trackingProtectionModule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SumiSettingsModuleToggleGate(descriptor: .trackingProtection) {
                if let settings = trackingProtectionModule.settingsIfEnabled(),
                   let dataStore = trackingProtectionModule.dataStoreIfEnabled() {
                    LegacyTrackingProtectionRuntimeSettingsView(
                        trackingProtectionModule: trackingProtectionModule,
                        trackingProtectionSettings: settings,
                        trackingProtectionDataStore: dataStore
                    )
                }
            }

            SumiSettingsModuleToggleGate(descriptor: .adBlocking)

            Spacer()
        }
    }
}

private struct LegacyTrackingProtectionRuntimeSettingsView: View {
    let trackingProtectionModule: SumiTrackingProtectionModule
    @ObservedObject var trackingProtectionSettings: SumiTrackingProtectionSettings
    @ObservedObject var trackingProtectionDataStore: SumiTrackingProtectionDataStore
    @State private var trackingOverrideHostInput = ""

    var body: some View {
        SettingsSection(
            title: "Tracking Protection Runtime",
            subtitle: "Controls the existing WebKit-native tracking rules while the module is enabled."
        ) {
            SettingsRow(
                title: "Protection mode",
                subtitle: trackingProtectionSettings.globalMode == .enabled
                    ? "Tracking Protection is enabled globally."
                    : "Tracking Protection is disabled globally."
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { trackingProtectionSettings.globalMode == .enabled },
                        set: { isEnabled in
                            trackingProtectionSettings.setGlobalMode(isEnabled ? .enabled : .disabled)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsDivider()
            trackingDataControls
            SettingsDivider()
            trackingSiteOverrides
        }
    }

    private var trackingDataControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow(title: "Last update", systemImage: "clock") {
                HStack(spacing: 8) {
                    Text(lastTrackerUpdateValue)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if trackingProtectionDataStore.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    }

                    Button {
                        Task {
                            await trackingProtectionModule.updateTrackerDataManually()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Update tracker data")
                    .help("Update tracker data")
                    .disabled(
                        trackingProtectionDataStore.isUpdating
                            || !trackingProtectionModule.isEnabled
                    )

                    if trackingProtectionDataStore.metadata.currentSource == .downloaded {
                        Button {
                            Task {
                                await trackingProtectionModule.resetTrackerDataToBundledManually()
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Reset to bundled tracker data")
                        .help("Reset to bundled tracker data")
                        .disabled(
                            trackingProtectionDataStore.isUpdating
                                || !trackingProtectionModule.isEnabled
                        )
                    }
                }
            }

            if let lastUpdateError = trackingProtectionDataStore.metadata.lastUpdateError,
               !lastUpdateError.isEmpty {
                Text("Last update error: \(lastUpdateError)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var lastTrackerUpdateValue: String {
        guard let lastUpdateDate = trackingProtectionDataStore.metadata.lastSuccessfulUpdateDate else {
            return "Never"
        }
        return formatTrackingUpdateDate(lastUpdateDate)
    }

    private var trackingSiteOverrides: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Site Overrides")
                .font(.subheadline)
                .fontWeight(.medium)

            if trackingProtectionSettings.sortedSiteOverrides.isEmpty {
                Text("No site overrides.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(trackingProtectionSettings.sortedSiteOverrides, id: \.host) { item in
                        SettingsRow(title: item.host) {
                            Menu(item.override.displayTitle) {
                                Button("Use Global Setting") {
                                    trackingProtectionSettings.removeSiteOverride(forNormalizedHost: item.host)
                                }
                                Button("Enable") {
                                    _ = trackingProtectionSettings.setSiteOverride(.enabled, forUserInput: item.host)
                                }
                                Button("Disable") {
                                    _ = trackingProtectionSettings.setSiteOverride(.disabled, forUserInput: item.host)
                                }
                            }
                            .menuStyle(.button)
                            .fixedSize()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("example.com", text: $trackingOverrideHostInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Menu("Add") {
                    Button("Enable for Site") {
                        addTrackingOverride(.enabled)
                    }
                    Button("Disable for Site") {
                        addTrackingOverride(.disabled)
                    }
                }
                .menuStyle(.button)
                .disabled(trackingOverrideHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func formatTrackingUpdateDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func addTrackingOverride(_ override: SumiTrackingProtectionSiteOverride) {
        if trackingProtectionSettings.setSiteOverride(
            override,
            forUserInput: trackingOverrideHostInput
        ) {
            trackingOverrideHostInput = ""
        }
    }
}

#Preview {
    PrivacySettingsView()
}
