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
        VStack(alignment: .leading, spacing: 20) {
            SumiSettingsModuleToggleGate(descriptor: .trackingProtection) {
                if let settings = trackingProtectionModule.settingsIfEnabled(),
                   let dataStore = trackingProtectionModule.dataStoreIfEnabled() {
                    LegacyTrackingProtectionRuntimeSettingsView(
                        trackingProtectionSettings: settings,
                        trackingProtectionDataStore: dataStore
                    )
                }
            }

            SumiSettingsModuleToggleGate(descriptor: .adBlocking)

            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct LegacyTrackingProtectionRuntimeSettingsView: View {
    @ObservedObject var trackingProtectionSettings: SumiTrackingProtectionSettings
    @ObservedObject var trackingProtectionDataStore: SumiTrackingProtectionDataStore
    @State private var trackingOverrideHostInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Current protection mode",
                isOn: Binding(
                    get: { trackingProtectionSettings.globalMode == .enabled },
                    set: { isEnabled in
                        trackingProtectionSettings.setGlobalMode(isEnabled ? .enabled : .disabled)
                    }
                )
            )

            Text("Controls the existing WebKit-native tracking rules while the Tracking Protection module is enabled.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            trackingDataControls

            Divider()

            trackingSiteOverrides
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var trackingDataControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Update tracker data") {
                    Task {
                        await trackingProtectionDataStore.updateTrackerData()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(trackingProtectionDataStore.isUpdating)

                if trackingProtectionDataStore.isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if trackingProtectionDataStore.metadata.currentSource == .downloaded {
                    Button("Reset to bundled tracker data") {
                        trackingProtectionDataStore.resetToBundled()
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 6) {
                Text("Current source:")
                    .foregroundColor(.secondary)
                Text(trackingProtectionDataStore.metadata.currentSource.rawValue)
                    .fontWeight(.medium)
            }
            .font(.caption)

            if let lastUpdateDate = trackingProtectionDataStore.metadata.lastSuccessfulUpdateDate {
                Text("Last successful update: \(formatTrackingUpdateDate(lastUpdateDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Last successful update: Never")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                        HStack {
                            Text(item.host)
                                .lineLimit(1)
                            Spacer()
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
                        .font(.caption)
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
