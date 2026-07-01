//
//  PrivacySettingsView.swift
//  Sumi
//
//

import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sumiProtectionCoordinator) private var protectionCoordinator
    let repository: SumiPermissionSettingsRepository
    let activeProfile: Profile?

    var body: some View {
        Group {
            if sumiSettings.privacySettingsRoute.isSiteSettings {
                SumiSiteSettingsView(
                    repository: repository,
                    profile: activeProfile,
                    initialFilter: sumiSettings.privacySettingsRoute.siteSettingsFilter
                ) {
                    sumiSettings.privacySettingsRoute = .overview
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSection(
                        title: SumiSiteSettingsStrings.title,
                        subtitle: SumiSiteSettingsStrings.subtitle
                    ) {
                        SumiSiteSettingsNavigationRow(
                            title: SumiSiteSettingsStrings.title,
                            subtitle: SumiSiteSettingsStrings.subtitle,
                            systemImage: "hand.raised"
                        ) {
                            sumiSettings.privacySettingsRoute = .siteSettings(nil)
                        }
                    }

                    AdblockProtectionSettingsView(
                        coordinator: protectionCoordinator
                    )

                    Spacer()
                }
            }
        }
    }
}

private struct AdblockProtectionSettingsView: View {
    let coordinator: SumiProtectionCoordinator
    @ObservedObject private var settings: SumiProtectionSettings
    @ObservedObject private var bundleUpdateStatus: SumiProtectionBundleUpdateStatusStore
    @State private var isApplying = false
    @State private var isUpdatingBundles = false

    init(
        coordinator: SumiProtectionCoordinator
    ) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
        _bundleUpdateStatus = ObservedObject(wrappedValue: coordinator.bundleUpdateStatusStore)
    }

    var body: some View {
        protectionSettingsSection
    }

    private var protectionSettingsSection: some View {
        SettingsSection(title: "Adblock & Protection") {
            levelControls

            if settings.browserRestartRequired {
                SettingsDivider()
                restartRequiredWarning
            }

            SettingsDivider()

            lastUpdateRow
        }
    }

    private var levelBinding: Binding<SumiProtectionLevel> {
        Binding(
            get: { settings.level },
            set: { level in
                coordinator.setLevel(level)
            }
        )
    }

    private var levelControls: some View {
        SettingsRow(
            title: "Protection level",
            subtitle: coordinator.applyNeeded ? "Apply changes to use the selected level." : nil
        ) {
            HStack(spacing: 8) {
                Picker("", selection: levelBinding) {
                    ForEach(SumiProtectionLevel.allCases) { level in
                        Text(level.displayTitle).tag(level)
                    }
                }
                .labelsHidden()
                .settingsTrailingControl(width: 150)

                Button {
                    applySelectedLevel()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44)
                    } else {
                        Text("Apply")
                            .frame(width: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isApplying || !coordinator.applyNeeded)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var lastUpdateRow: some View {
        SettingsRow(
            title: "Last update",
            subtitle: lastUpdateErrorText ?? lastUpdateText
        ) {
            Button {
                updatePreparedBundles()
            } label: {
                if isUpdatingBundles {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating")
                    }
                } else {
                    Label("Update", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isUpdatingBundles)
        }
    }

    private var restartRequiredWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 18, height: 18)

            Text("Restart Sumi to apply this change.")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var globalDiagnostics: SumiProtectionGlobalDiagnostics {
        coordinator.globalDiagnostics()
    }

    private var lastUpdateText: String {
        let global = globalDiagnostics
        if let date = global.lastSuccessfulBundleInstallDate ?? bundleUpdateStatus.lastSuccessDate {
            return settingsDateString(date)
        }
        return "Never"
    }

    private var lastUpdateErrorText: String? {
        guard let reason = bundleUpdateStatus.lastFailureReason else { return nil }
        return "Update failed: \(Self.compactUpdateError(reason))"
    }

    private func applySelectedLevel() {
        guard !isApplying else { return }
        isApplying = true
        Task {
            do {
                let _ = try await coordinator.applySelectedLevel()
                await MainActor.run {
                    isApplying = false
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                }
            }
        }
    }

    private func updatePreparedBundles() {
        guard !isUpdatingBundles else { return }
        isUpdatingBundles = true
        Task {
            do {
                let _ = try await coordinator.updatePreparedBundlesManually()
                await MainActor.run {
                    isUpdatingBundles = false
                }
            } catch {
                await MainActor.run {
                    isUpdatingBundles = false
                }
            }
        }
    }

    private func settingsDateString(_ date: Date) -> String {
        Self.settingsDateFormatter.string(from: date)
    }

    private static let settingsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func compactUpdateError(_ reason: String) -> String {
        let singleLine = reason
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 140
        guard singleLine.count > limit else { return singleLine }
        return "\(singleLine.prefix(limit))..."
    }
}
