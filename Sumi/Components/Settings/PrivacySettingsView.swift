//
//  PrivacySettingsView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sumiTrackingProtectionModule) private var trackingProtectionModule
    @Environment(\.sumiAdBlockingModule) private var adBlockingModule
    @ObservedObject var browserManager: BrowserManager
    var windowState: BrowserWindowState?

    var body: some View {
        Group {
            if sumiSettings.privacySettingsRoute.isSiteSettings {
                SumiSiteSettingsView(
                    repository: SumiPermissionSettingsRepository(browserManager: browserManager),
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

                    SumiSettingsModuleToggleGate(descriptor: .adBlocking) {
                        if let settings = adBlockingModule.settingsIfEnabled() {
                            NativeAdblockSettingsView(
                                settings: settings,
                                sitePolicyStore: adBlockingModule.sitePolicyStoreIfEnabled(),
                                adBlockingModule: adBlockingModule,
                                currentTab: currentTab
                            )
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    private var activeProfile: Profile? {
        if let windowState {
            if windowState.isIncognito {
                return windowState.ephemeralProfile
            }
            if let currentProfileId = windowState.currentProfileId,
               let profile = browserManager.profileManager.profiles.first(where: { $0.id == currentProfileId }) {
                return profile
            }
            if let currentTab = browserManager.currentTab(for: windowState),
               let profileId = currentTab.profileId,
               let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
                return profile
            }
        }
        return browserManager.currentProfile
    }

    private var currentTab: Tab? {
        guard let windowState else { return nil }
        return browserManager.currentTab(for: windowState)
    }
}

private struct NativeAdblockSettingsView: View {
    @ObservedObject var settings: AdblockSettingsStore
    @ObservedObject var sitePolicyStore: AdblockSitePolicyStore
    let adBlockingModule: SumiAdBlockingModule
    let currentTab: Tab?
    private let registry = AdblockFilterListRegistry()
    @State private var overrideHostInput = ""
    #if DEBUG
    @State private var rebuildStatus: String?
    @State private var isRebuilding = false
    #endif

    var body: some View {
        SettingsSection(
            title: "Native Ad Blocking",
            subtitle: "Uses WebKit content blocking. Native modes stay script-free; enhanced cleanup remains explicit opt-in."
        ) {
            SettingsRow(
                title: "Automatic filter updates",
                subtitle: "Stored for future list updates; no background updater runs in this skeleton."
            ) {
                Toggle("", isOn: $settings.autoUpdateEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsRow(
                title: "Cosmetic filtering",
                subtitle: settings.cosmeticMode.detail
            ) {
                Picker("", selection: $settings.cosmeticMode) {
                    ForEach(SumiAdblockCosmeticMode.allCases) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            #if DEBUG
            SettingsRow(
                title: "Native profile",
                subtitle: debugNativeProfileSubtitle
            ) {
                Picker(
                    "",
                    selection: Binding(
                        get: { settings.selectedNativeProfile },
                        set: { profile in
                            _ = settings.setSelectedNativeProfile(
                                profile,
                                registry: registry,
                                allowDeveloperOnly: true
                            )
                        }
                    )
                ) {
                    ForEach(registry.comparisonProfiles) { profile in
                        Text(debugProfileLabel(profile)).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }
            debugDiagnosticsSection
            #endif

            SettingsRow(
                title: "Filter lists",
                subtitle: listSelectionStatus
            ) {
                Text("\(selectedListCount) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            filterListSelection
            SettingsDivider()
            adblockSiteOverrides
        }
    }

    private var listSelectionStatus: String {
        settings.listSelectionRequiresUpdate
            ? "Selection saved. Run a manual update to compile the new list set."
            : "Choose base, regional, and optional annoyance lists."
    }

    private var selectedListCount: Int {
        registry.validatedSelection(
            settings.selectedLists,
            profileKind: settings.selectedNativeProfile
        ).resolvedIdentifiers.count
    }

    #if DEBUG
    private var debugNativeProfileSubtitle: String {
        if debugDiagnostics.generationIsStale {
            return "Generation is stale. Rebuild selected Adblock profile now before measuring score."
        }
        return "Developer-only comparison preset. Changes require a manual update and page reload."
    }

    private func debugProfileLabel(_ profile: AdblockFilterListProfile) -> String {
        switch profile.exposure {
        case .productionDefault:
            return "Sumi Default"
        case .developerOnly:
            return profile.displayName
        }
    }

    private var debugDiagnostics: SumiAdblockAttachmentDiagnostics {
        adBlockingModule.attachmentDiagnostics(for: currentTab?.url)
    }

    private var debugTabDiagnostics: SumiAdblockCurrentTabDiagnostics? {
        currentTab?.adblockCurrentTabDiagnostics()
    }

    private var debugDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsDivider()

            Text("DEBUG Adblock Diagnostics")
                .font(.subheadline)
                .fontWeight(.medium)

            if debugDiagnostics.generationIsStale {
                Text("Current generation is stale. Rebuild/update before measuring score.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            SettingsRow(
                title: "Rebuild selected Adblock profile now",
                subtitle: rebuildStatus ?? "Downloads selected lists if needed, compiles the selected native profile, and publishes shards transactionally."
            ) {
                Button {
                    rebuildSelectedProfile()
                } label: {
                    if isRebuilding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Rebuild")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRebuilding)
            }

            debugKeyValueGrid(rows: debugGlobalRows)

            if let tabDiagnostics = debugTabDiagnostics {
                SettingsDivider()
                Text("DEBUG Current Tab Attachment")
                    .font(.subheadline)
                    .fontWeight(.medium)
                debugKeyValueGrid(rows: debugTabRows(tabDiagnostics))
            }
        }
    }

    private var debugGlobalRows: [(String, String)] {
        let diagnostics = debugDiagnostics
        return [
            ("Global enabled", diagnostics.globalAdblockEnabled.description),
            ("Selected profile", diagnostics.selectedNativeProfile?.rawValue ?? "nil"),
            ("Active compiled profile", diagnostics.activeCompiledNativeProfile?.rawValue ?? "nil"),
            ("Selected differs from active", diagnostics.selectedProfileDiffersFromActiveGeneration.description),
            ("Generation stale", diagnostics.generationIsStale.description),
            ("Last successful rebuild", debugDateString(diagnostics.lastSuccessfulUpdateDate)),
            ("Last rebuild error", diagnostics.lastUpdateError ?? "nil"),
            ("Selected list IDs", diagnostics.selectedListIdentifiers.joined(separator: ", ")),
            ("Active manifest list IDs", diagnostics.activeManifestListIdentifiers.joined(separator: ", ")),
            ("Native compiler", diagnostics.nativeCompiler.map { "\($0.name) \($0.version)" } ?? "nil"),
            ("Network shard count", diagnostics.networkShardCount.description),
            ("Native CSS shard count", diagnostics.nativeCSSShardCount.description),
            ("Total network rules", diagnostics.totalNetworkRuleCount.description),
            ("Total native CSS rules", diagnostics.totalNativeCSSRuleCount.description),
            ("Largest shard JSON bytes", diagnostics.largestShardJSONByteCount.description),
            ("Cap/discard", debugRuleCapString(diagnostics)),
            ("Cosmetic mode", diagnostics.cosmeticMode?.rawValue ?? "nil"),
            ("Enhanced runtime", diagnostics.enhancedRuntimeIsEnabled.description),
            ("Tracking Protection", diagnostics.trackingProtectionModuleEnabled.description),
        ]
    }

    private func debugTabRows(_ diagnostics: SumiAdblockCurrentTabDiagnostics) -> [(String, String)] {
        [
            ("URL", diagnostics.urlString ?? "nil"),
            ("Host", diagnostics.host ?? "nil"),
            ("Normalized site key", diagnostics.normalizedSiteKey ?? "nil"),
            ("Global Adblock", diagnostics.globalAdblockEnabled.description),
            ("Per-site Adblock", diagnostics.perSiteAdblockEnabled.description),
            ("Reload required", diagnostics.reloadRequired.description),
            ("Active generation", diagnostics.activeGenerationId ?? "nil"),
            ("Selected profile", diagnostics.selectedNativeProfile?.rawValue ?? "nil"),
            ("Active compiled profile", diagnostics.activeCompiledNativeProfile?.rawValue ?? "nil"),
            ("Cosmetic mode", diagnostics.cosmeticMode?.rawValue ?? "nil"),
            ("Expected network shards", diagnostics.expectedNetworkShardIdentifiers.joined(separator: ", ")),
            ("Expected native CSS shards", diagnostics.expectedNativeCSSShardIdentifiers.joined(separator: ", ")),
            ("Attached network shards", diagnostics.attachedNetworkShardIdentifiers.joined(separator: ", ")),
            ("Attached native CSS shards", diagnostics.attachedNativeCSSShardIdentifiers.joined(separator: ", ")),
            ("Missing shards", diagnostics.missingShardIdentifiers.joined(separator: ", ")),
            ("Ineligible surface", diagnostics.ineligibleSurfaceReason ?? "nil"),
        ]
    }

    private func debugKeyValueGrid(rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.1.isEmpty ? "[]" : row.1)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }

    private func rebuildSelectedProfile() {
        guard !isRebuilding else { return }
        isRebuilding = true
        rebuildStatus = nil
        Task {
            do {
                let manifest = try await adBlockingModule.rebuildSelectedAdblockProfileNow()
                await MainActor.run {
                    if let manifest {
                        rebuildStatus = "Rebuilt \(manifest.nativeProfile?.rawValue ?? "unknown") at \(debugDateString(manifest.lastSuccessfulUpdateDate)). Reload the test tab before measuring."
                    } else {
                        rebuildStatus = "No rebuild ran. Enable built-in Adblock before rebuilding."
                    }
                    currentTab?.updateAdblockReloadRequirementForCurrentSite()
                    isRebuilding = false
                }
            } catch {
                await MainActor.run {
                    rebuildStatus = "Rebuild failed: \(error.localizedDescription)"
                    isRebuilding = false
                }
            }
        }
    }

    private func debugDateString(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return Self.debugDateFormatter.string(from: date)
    }

    private func debugRuleCapString(_ diagnostics: SumiAdblockAttachmentDiagnostics) -> String {
        guard let cap = diagnostics.nativeCompilationSummary?.ruleCap else { return "nil" }
        return "hit=\(cap.wasHit) discarded=\(cap.discardedRuleCount)"
    }

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
    #endif

    private var filterListSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(displayedCategories, id: \.self) { category in
                DisclosureGroup(categoryTitle(category)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(descriptors(in: category)) { descriptor in
                            filterListRow(descriptor)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var displayedCategories: [AdblockFilterListCategory] {
        [.baseAds, .nativeCosmeticCompatibleAds, .regional, .annoyances, .privacyOverlap]
    }

    private func descriptors(in category: AdblockFilterListCategory) -> [AdblockFilterListDescriptor] {
        registry.descriptors
            .filter { $0.category == category }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func categoryTitle(_ category: AdblockFilterListCategory) -> String {
        switch category {
        case .baseAds:
            return "Base ads"
        case .nativeCosmeticCompatibleAds:
            return "Base variants"
        case .annoyances:
            return "Annoyances, cookies, and social"
        case .regional:
            return "Regional ads"
        case .privacyOverlap:
            return "Privacy overlap"
        }
    }

    private func filterListRow(_ descriptor: AdblockFilterListDescriptor) -> some View {
        SettingsRow(
            title: descriptor.displayName,
            subtitle: filterListSubtitle(descriptor)
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: {
                        settings.isListSelected(descriptor, registry: registry)
                    },
                    set: { isSelected in
                        settings.setList(descriptor, isSelected: isSelected, registry: registry)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!descriptor.isAllowedInNativeOnlyMode)
            .help(descriptor.isAllowedInNativeOnlyMode ? descriptor.shortDescription : "Not compatible with native-only mode")
        }
    }

    private func filterListSubtitle(_ descriptor: AdblockFilterListDescriptor) -> String {
        var parts = [descriptor.shortDescription]
        if descriptor.mayContainCosmeticFilters {
            parts.append("May include native CSS hiding rules.")
        } else {
            parts.append("Network-only variant.")
        }
        if let variantOf = descriptor.variantOfListId {
            parts.append("Variant of \(variantOf); mutually exclusive.")
        }
        if descriptor.category == .privacyOverlap {
            parts.append("Disabled by default while Tracking Protection is separate.")
        }
        parts.append(descriptor.licenseNoticeHint)
        return parts.joined(separator: " ")
    }

    private var adblockSiteOverrides: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Site Overrides")
                .font(.subheadline)
                .fontWeight(.medium)

            if sitePolicyStore.sortedSiteOverrides.isEmpty {
                Text("No site overrides.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sitePolicyStore.sortedSiteOverrides, id: \.host) { item in
                        SettingsRow(title: item.host) {
                            Menu(item.override.displayTitle) {
                                Button("Use Global Setting") {
                                    sitePolicyStore.removeSiteOverride(forNormalizedHost: item.host)
                                }
                                Button("Enable") {
                                    _ = sitePolicyStore.setSiteOverride(.allowed, forUserInput: item.host)
                                }
                                Button("Disable") {
                                    _ = sitePolicyStore.setSiteOverride(.disabled, forUserInput: item.host)
                                }
                            }
                            .menuStyle(.button)
                            .fixedSize()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("example.com", text: $overrideHostInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Menu("Add") {
                    Button("Enable for Site") {
                        addOverride(.allowed)
                    }
                    Button("Disable for Site") {
                        addOverride(.disabled)
                    }
                }
                .menuStyle(.button)
                .disabled(overrideHostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addOverride(_ override: SumiAdblockSiteOverride) {
        if sitePolicyStore.setSiteOverride(override, forUserInput: overrideHostInput) {
            overrideHostInput = ""
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
    PrivacySettingsView(browserManager: BrowserManager(), windowState: nil)
}
