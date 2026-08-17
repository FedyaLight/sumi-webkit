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
                        AdblockSettingsView(
                            coordinator: protectionCoordinator
                        )
                    } else {
                        SettingsSection(title: "Adblock") {
                            Text("Adblock settings are unavailable outside the browser runtime.")
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

private struct AdblockSettingsView: View {
    let coordinator: SumiProtectionCoordinator
    @ObservedObject private var settings: SumiProtectionSettings
    @State private var isApplying = false
    @State private var presentedNotification: BrowserNotification?

    init(coordinator: SumiProtectionCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsFeatureToggleCard(
                title: "Adblock",
                isEnabled: enabledBinding
            )
            .accessibilityIdentifier("privacy-adblock-enabled")

            if settings.level == .adblock,
               let catalog = coordinator.filterListCatalog {
                AdblockFilterListsSection(
                    catalog: catalog,
                    selectedIDs: settings.selectedFilterListIDs(in: catalog),
                    statusText: filterListStatusText(in: catalog),
                    isApplying: isApplying,
                    resetToDefaults: coordinator.resetFilterListsToDefaults,
                    setEnabled: coordinator.setFilterList,
                    apply: applySelectedLevel
                )
            } else if hasPendingChanges {
                AdblockPendingDisableSection(
                    statusText: lastUpdateErrorText
                        ?? "Apply changes to turn off Adblock.",
                    isApplying: isApplying,
                    apply: applySelectedLevel
                )
            }
        }
            .alert(item: $presentedNotification) { notification in
                Alert(
                    title: Text(notification.title),
                    message: notification.subtitle.map(Text.init),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.level == .adblock },
            set: { coordinator.setLevel($0 ? .adblock : .off) }
        )
    }

    private var hasPendingChanges: Bool {
        guard settings.level == settings.appliedLevel else { return true }
        guard settings.level == .adblock,
              let catalog = coordinator.filterListCatalog else { return false }
        return settings.filterListSelectionApplyNeeded(in: catalog)
    }

    private var lastUpdateText: String {
        if let date = coordinator.lastSuccessfulUpdateDate {
            return settingsDateString(date)
        }
        return "Never"
    }

    private var lastUpdateErrorText: String? {
        guard let reason = coordinator.lastApplyError else { return nil }
        return "Update failed: \(Self.compactUpdateError(reason))"
    }

    private func filterListStatusText(
        in catalog: SumiFilterListCatalog
    ) -> String {
        if let lastUpdateErrorText {
            return lastUpdateErrorText
        }
        let selectedCount = settings.selectedFilterListIDs(in: catalog).count
        let selectionText = "\(selectedCount) of \(catalog.lists.count) enabled"
        if hasPendingChanges {
            return "\(selectionText). Changes not applied."
        }
        return "\(selectionText). Last updated \(lastUpdateText)."
    }

    private func applySelectedLevel() {
        guard !isApplying else { return }
        isApplying = true
        Task {
            do {
                try await coordinator.applySelectedLevel()
                await MainActor.run {
                    isApplying = false
                    presentedNotification =
                        .protectionLevelApplied(
                            levelTitle: settings.appliedLevel.displayTitle
                        )
                }
            } catch {
                await MainActor.run {
                    isApplying = false
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

private struct AdblockFilterListsSection: View {
    let catalog: SumiFilterListCatalog
    let selectedIDs: Set<String>
    let statusText: String
    let isApplying: Bool
    let resetToDefaults: () -> Void
    let setEnabled: (String, Bool) -> Void
    let apply: () -> Void

    var body: some View {
        SettingsSection(
            title: "Filter lists",
            subtitle: statusText,
            headerAccessory: {
                AdblockFilterActions(
                    defaultsDisabled: selectedIDs == catalog.defaultEnabledIDs,
                    isApplying: isApplying,
                    resetToDefaults: resetToDefaults,
                    apply: apply
                )
            }
        ) {
            ForEach(
                Array(catalog.categories.enumerated()),
                id: \.element
            ) { index, category in
                if index > 0 {
                    SettingsDivider()
                }
                AdblockFilterListCategoryView(
                    category: category,
                    lists: catalog.lists.filter { $0.category == category },
                    selectedIDs: selectedIDs,
                    setEnabled: setEnabled
                )
            }
        }
    }
}

private struct AdblockPendingDisableSection: View {
    let statusText: String
    let isApplying: Bool
    let apply: () -> Void

    var body: some View {
        SettingsSection(
            subtitle: statusText,
            headerAccessory: {
                AdblockFilterActions(
                    defaultsDisabled: true,
                    isApplying: isApplying,
                    resetToDefaults: {},
                    apply: apply
                )
            }
        ) {
            EmptyView()
        }
    }
}

private struct AdblockFilterActions: View {
    let defaultsDisabled: Bool
    let isApplying: Bool
    let resetToDefaults: () -> Void
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: resetToDefaults) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(defaultsDisabled || isApplying)
            .accessibilityLabel("Restore default filter lists")
            .accessibilityIdentifier("privacy-reset-filter-lists")
            .help("Restore default filter lists")

            Button(action: apply) {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 50)
                } else {
                    Text("Apply")
                        .frame(width: 50)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isApplying)
            .accessibilityIdentifier("privacy-apply-adblock")
            .help("Apply Adblock changes")
        }
    }
}

private struct AdblockFilterListCategoryView: View {
    let category: SumiFilterListCatalog.List.Category
    let lists: [SumiFilterListCatalog.List]
    let selectedIDs: Set<String>
    let setEnabled: (String, Bool) -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lists) { list in
                    AdblockFilterListRow(
                        list: list,
                        isEnabled: selectedIDs.contains(list.id),
                        setEnabled: setEnabled
                    )
                }
            }
            .padding(.top, 6)
        } label: {
            Button {
                isExpanded.toggle()
            } label: {
                Text(category.displayTitle)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AdblockFilterListRow: View {
    let list: SumiFilterListCatalog.List
    let isEnabled: Bool
    let setEnabled: (String, Bool) -> Void

    var body: some View {
        SettingsRow(
            title: list.displayName,
            subtitle: subtitle,
            verticalPadding: 7
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { setEnabled(list.id, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(list.displayName)
            .accessibilityIdentifier("privacy-filter-list-\(list.id)")
        }
    }

    private var subtitle: String? {
        let parts = [
            list.defaultEnabled ? "Recommended" : nil,
            list.description.isEmpty ? nil : list.description,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
