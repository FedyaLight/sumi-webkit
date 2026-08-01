//
//  PrivacySettingsView.swift
//  Sumi
//
//

import SumiDomain
import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sumiProtectionCoordinator) private var protectionCoordinator
    @EnvironmentObject private var toolbarOwner: SettingsWindowToolbarOwner
    let repository: SumiPermissionSettingsRepository
    let activeProfile: Profile?

    var body: some View {
        @Bindable var settings = sumiSettings

        Group {
            if sumiSettings.privacySettingsRoute.isSiteSettings {
                SumiSiteSettingsView(
                    repository: repository,
                    profile: activeProfile,
                    initialFilter: sumiSettings.privacySettingsRoute.siteSettingsFilter
                ) {
                    let previousFilter = sumiSettings.privacySettingsRoute.siteSettingsFilter
                    sumiSettings.privacySettingsRoute = .overview
                    toolbarOwner.show(
                        title: String(localized: "Privacy & Security"),
                        backAction: nil,
                        forwardAction: {
                            sumiSettings.privacySettingsRoute = .siteSettings(previousFilter)
                        }
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection {
                        SumiSiteSettingsNavigationRow(
                            title: SumiSiteSettingsStrings.title,
                            subtitle: SumiSiteSettingsStrings.subtitle,
                            systemImage: "hand.raised"
                        ) {
                            sumiSettings.privacySettingsRoute = .siteSettings(nil)
                        }
                        .accessibilityIdentifier("privacy-site-settings")
                    }

                    if let protectionCoordinator {
                        AdblockProtectionSettingsView(
                            coordinator: protectionCoordinator
                        )
                    } else {
                        SettingsSection(title: "Adblock & Protection") {
                            Text("Protection settings are unavailable outside the browser runtime.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlobalPrivacyControlSettingsView(isGPCEnabled: $settings.isGPCEnabled)

                    Spacer()
                }
            }
        }
    }
}

private struct GlobalPrivacyControlSettingsView: View {
    @Binding var isGPCEnabled: Bool

    var body: some View {
        SettingsSection(
            title: String(
                localized: "Global Privacy Control",
                comment: "Privacy setting title."
            ),
            subtitle: String(
                localized: "Tell every site you visit that you don't want your data sold or shared.",
                comment: "Explains the Global Privacy Control setting."
            ),
            headerAccessory: {
                Toggle("", isOn: $isGPCEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Global Privacy Control")
                    .accessibilityIdentifier("privacy-global-privacy-control")
                    .help("Tell sites not to sell or share your data")
            }
        ) {
            EmptyView()
        }
    }
}

private struct AdblockProtectionSettingsView: View {
    let coordinator: SumiProtectionCoordinator
    @ObservedObject private var settings: SumiProtectionSettings
    @ObservedObject private var bundleUpdateStatus: SumiProtectionBundleUpdateStatusStore
    @State private var isApplying = false
    @State private var isUpdatingBundles = false
    @State private var presentedNotification: BrowserNotification?

    init(coordinator: SumiProtectionCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
        _bundleUpdateStatus = ObservedObject(wrappedValue: coordinator.bundleUpdateStatusStore)
    }

    var body: some View {
        protectionSettingsSection
            .alert(item: $presentedNotification) { notification in
                Alert(
                    title: Text(notification.title),
                    message: notification.subtitle.map(Text.init),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    private var protectionSettingsSection: some View {
        SettingsSection(title: "Adblock & Protection") {
            levelControls

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
            subtitle: levelSubtitle
        ) {
            HStack(spacing: 8) {
                Picker("", selection: levelBinding) {
                    ForEach(SumiProtectionLevel.allCases) { level in
                        Text(level.displayTitle).tag(level)
                    }
                }
                .settingsMenuPicker(width: 150)
                .accessibilityLabel("Protection level")
                .accessibilityIdentifier("privacy-protection-level")

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
                .controlSize(.small)
                .disabled(isApplying || !coordinator.applyNeeded)
                .accessibilityIdentifier("privacy-apply-protection-level")
                .help("Apply the selected protection level")
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
            .accessibilityIdentifier("privacy-update-protection-bundles")
            .help("Check for updated protection lists")
        }
    }

    /// Restart-required is announced as a toast when it happens; the row keeps a
    /// quiet trace of it so the pending restart stays discoverable afterwards.
    private var levelSubtitle: String? {
        if coordinator.applyNeeded {
            return "Apply changes to use the selected level."
        }
        if settings.browserRestartRequired {
            return "Restart Sumi to finish applying this level."
        }
        return nil
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
                let outcome = try await coordinator.applySelectedLevel()
                await MainActor.run {
                    isApplying = false
                    if settings.browserRestartRequired {
                        presentedNotification =
                            .protectionLevelApplied(
                                levelTitle: outcome.appliedLevel.displayTitle
                            )
                    }
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
                let outcome = try await coordinator.updatePreparedBundlesManually()
                await MainActor.run {
                    isUpdatingBundles = false
                    if outcome.activation == .installedRestartRequired {
                        presentedNotification =
                            .protectionBundlesUpdated(releaseVersion: outcome.releaseVersion)
                    }
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
