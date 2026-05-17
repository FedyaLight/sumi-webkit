//
//  PrivacySettingsView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import AppKit
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
                                browserManager: browserManager,
                                windowState: windowState,
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
    let browserManager: BrowserManager
    let windowState: BrowserWindowState?
    let currentTab: Tab?
    private let registry = AdblockFilterListRegistry()
    @State private var overrideHostInput = ""
    #if DEBUG
    @State private var rebuildStatus: String?
    @State private var copyDiagnosticsStatus: String?
    @State private var resetListsStatus: String?
    @State private var selectedEmbeddedBundleProfileId = "currentDefault"
    @State private var embeddedBundleInstallStatus: String?
    @State private var isRebuilding = false
    @State private var isInstallingEmbeddedBundle = false
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
                title: "Runtime-generated dev profile",
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
            debugEmbeddedBundleSection
            debugDiagnosticsSection
            #endif

            SettingsRow(
                title: "Effective mode",
                subtitle: effectiveModeSubtitle
            ) {
                Text(effectiveModeTitle)
                    .font(.callout)
                    .foregroundColor(effectiveSelectionDiagnostics.isCustomListSelection ? .orange : .secondary)
            }

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

    private var effectiveSelectionDiagnostics: AdblockEffectiveSelectionDiagnostics {
        registry.effectiveSelectionDiagnostics(
            selection: settings.selectedLists,
            profileKind: settings.selectedNativeProfile
        )
    }

    private var effectiveModeTitle: String {
        effectiveSelectionDiagnostics.isCustomListSelection
            ? "Custom list selection"
            : selectedProfileDisplayName
    }

    private var effectiveModeSubtitle: String {
        if effectiveSelectionDiagnostics.isCustomListSelection {
            return "Manual list toggles differ from the selected profile. Rebuild will compile the final effective list set, not the profile baseline."
        }
        return "Using the selected profile-derived list set."
    }

    private var selectedProfileDisplayName: String {
        let profile = registry.profile(for: settings.selectedNativeProfile)
        switch profile.exposure {
        case .productionDefault:
            return "Sumi default list set"
        case .developerOnly:
#if DEBUG
            return profile.displayName
#else
            return "Custom list selection"
#endif
        }
    }

    private var selectedListCount: Int {
        effectiveSelectionDiagnostics.finalEffectiveListIdentifiers.count
    }

    #if DEBUG
    private var debugNativeProfileSubtitle: String {
        if effectiveSelectionDiagnostics.isCustomListSelection {
            return "Controls the old runtime-generated path, not embedded bundles. Effective mode is Custom list selection."
        }
        if debugDiagnostics.generationIsStale {
            return "Controls the old runtime-generated path, not embedded bundles. Generation is stale until rebuilt."
        }
        return "Controls the old runtime-generated path, not embedded bundles. Changes require a rebuild and page reload."
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
        adBlockingModule.attachmentDiagnostics(for: debugDiagnosticsTarget.url)
    }

    private var debugTabDiagnostics: SumiAdblockCurrentTabDiagnostics? {
        debugDiagnosticsTarget.tab?.adblockCurrentTabDiagnostics()
    }

    private var debugDiagnosticsTarget: DebugAdblockDiagnosticsTarget {
        let currentEligibility = adBlockingModule.surfaceEligibility(for: currentTab?.url)
        if let currentTab, currentEligibility.isEligible {
            return DebugAdblockDiagnosticsTarget(
                tab: currentTab,
                url: currentTab.url,
                source: "current tab"
            )
        }

        if let fallback = browserManager.lastActiveAdblockEligibleNormalWebTab(
            in: windowState,
            excluding: currentTab
        ) {
            let source: String
            if let reason = currentEligibility.ineligibleReason {
                source = "last eligible web tab (current tab ineligible: \(reason))"
            } else {
                source = "last eligible web tab"
            }
            return DebugAdblockDiagnosticsTarget(
                tab: fallback,
                url: fallback.url,
                source: source
            )
        }

        return DebugAdblockDiagnosticsTarget(
            tab: currentTab,
            url: currentTab?.url,
            source: currentEligibility.ineligibleReason.map {
                "current tab (ineligible: \($0))"
            } ?? "current tab"
        )
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

            if effectiveSelectionDiagnostics.isCustomListSelection {
                Text("Effective mode: Custom list selection. Manual lists override the selected profile baseline.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !debugBudgetWarnings.isEmpty {
                ForEach(debugBudgetWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            SettingsRow(
                title: "Reset lists to selected profile",
                subtitle: resetListsStatus ?? "Runtime-generated profiles only. This does not select or install an embedded bundle."
            ) {
                Button("Reset") {
                    resetListsToSelectedProfile()
                }
                .buttonStyle(.bordered)
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

            SettingsRow(
                title: "Copy Adblock Diagnostics",
                subtitle: copyDiagnosticsStatus ?? "Copy the active generation, target tab attachment, list selection, and failure diagnostics."
            ) {
                Button("Copy") {
                    copyAdblockDiagnostics()
                }
                .buttonStyle(.bordered)
            }

            debugKeyValueGrid(rows: debugGlobalRows)

            if !debugDiagnostics.lastUpdateListStatuses.isEmpty {
                SettingsDivider()
                Text("DEBUG Adblock List Updates")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ForEach(debugDiagnostics.lastUpdateListStatuses) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                        debugKeyValueGrid(rows: debugListRows(status))
                    }
                }
            }

            if let tabDiagnostics = debugTabDiagnostics {
                SettingsDivider()
                Text("DEBUG Current Tab Attachment")
                    .font(.subheadline)
                    .fontWeight(.medium)
                debugKeyValueGrid(rows: debugTabRows(tabDiagnostics))
            }
        }
    }

    private var debugEmbeddedBundleSection: some View {
        let snapshot = adBlockingModule.embeddedAdblockBundleSnapshot()
        let profiles = snapshot.installableProfiles

        return VStack(alignment: .leading, spacing: 10) {
            SettingsDivider()

            Text("Embedded Adblock Bundle")
                .font(.subheadline)
                .fontWeight(.medium)

            if profiles.isEmpty {
                Text("No embedded Adblock bundle found")
                    .font(.caption)
                    .foregroundStyle(.orange)

                debugKeyValueGrid(rows: [
                    ("Expected resource path", snapshot.expectedResourcePath),
                    ("Generate command", snapshot.generateCommand),
                    ("Generated bundle root", snapshot.generatedBundlesRootPath),
                    ("Generated outside app resources", snapshot.generatedBundlesPresentOutsideAppResources.description),
                ])
            } else {
                SettingsRow(
                    title: "Embedded bundle profile",
                    subtitle: selectedEmbeddedBundleSubtitle
                ) {
                    Picker("", selection: $selectedEmbeddedBundleProfileId) {
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }

                SettingsRow(
                    title: "Install selected embedded bundle",
                    subtitle: embeddedBundleInstallStatus ?? "Installs the selected embedded bundle through the native content-blocking publisher."
                ) {
                    Button {
                        installSelectedEmbeddedBundle()
                    } label: {
                        if isInstallingEmbeddedBundle {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstallingEmbeddedBundle || selectedEmbeddedBundleProfile == nil)
                }

                debugKeyValueGrid(rows: debugEmbeddedBundleRows(snapshot))
            }
        }
    }

    private var selectedEmbeddedBundleProfile: SumiEmbeddedAdblockBundleProfile? {
        let profiles = adBlockingModule.embeddedAdblockBundleSnapshot().installableProfiles
        return profiles.first { $0.id == selectedEmbeddedBundleProfileId } ?? profiles.first
    }

    private var selectedEmbeddedBundleSubtitle: String {
        guard let profile = selectedEmbeddedBundleProfile else {
            return "No installable embedded bundle profile is available."
        }
        return "bundleId=\(profile.bundleId ?? "nil"); generation=\(profile.generationId ?? "nil")"
    }

    private func debugEmbeddedBundleRows(_ snapshot: SumiEmbeddedAdblockBundleSnapshot) -> [(String, String)] {
        var rows = [
            ("Expected resource path", snapshot.expectedResourcePath),
            ("Generated bundle root", snapshot.generatedBundlesRootPath),
            ("Generated outside app resources", snapshot.generatedBundlesPresentOutsideAppResources.description),
        ]
        if let profile = selectedEmbeddedBundleProfile {
            rows.append(contentsOf: [
                ("Bundle profile id", profile.id),
                ("Native bundle id", profile.bundleId ?? "nil"),
                ("Bundle generation id", profile.generationId ?? "nil"),
                ("Bundle path", profile.bundleURL.path),
                ("Network shards", profile.networkShardCount.description),
                ("Native CSS shards", profile.nativeCSSShardCount.description),
                ("Network rules", profile.networkRuleCount.description),
                ("Native CSS rules", profile.nativeCSSRuleCount.description),
            ])
        }
        return rows
    }

    private var debugGlobalRows: [(String, String)] {
        let diagnostics = debugDiagnostics
        return [
            ("Diagnostics target", debugDiagnosticsTarget.source),
            ("Diagnostics URL", debugDiagnosticsTarget.url?.absoluteString ?? "nil"),
            ("Diagnostics target ineligible", diagnostics.ineligibleSurfaceReason ?? "nil"),
            ("Global enabled", diagnostics.globalAdblockEnabled.description),
            ("Effective mode", diagnostics.effectiveSelectionDiagnostics?.effectiveModeLabel ?? effectiveModeTitle),
            ("Selected profile", diagnostics.selectedNativeProfile?.rawValue ?? "nil"),
            ("Active compiled profile", diagnostics.activeCompiledNativeProfile?.rawValue ?? "nil"),
            ("Selected differs from active", diagnostics.selectedProfileDiffersFromActiveGeneration.description),
            ("Generation stale", diagnostics.generationIsStale.description),
            ("Generation source", diagnostics.generationSource?.rawValue ?? "nil"),
            ("Native bundle id", diagnostics.nativeRuleBundleId ?? "nil"),
            ("Previous generation retained", diagnostics.previousGenerationRetained.description),
            ("Last successful rebuild", debugDateString(diagnostics.lastSuccessfulUpdateDate)),
            ("Last rebuild error", diagnostics.lastUpdateError ?? "nil"),
            ("Last failure stage", diagnostics.lastUpdateFailureStage?.rawValue ?? "nil"),
            ("Selected list IDs", diagnostics.selectedListIdentifiers.joined(separator: ", ")),
            ("Manual selected list IDs", diagnostics.effectiveSelectionDiagnostics?.manuallySelectedListIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Profile-derived list IDs", diagnostics.effectiveSelectionDiagnostics?.profileDerivedListIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Recommended regional IDs", diagnostics.effectiveSelectionDiagnostics?.recommendedRegionalListIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Final effective list IDs", diagnostics.effectiveSelectionDiagnostics?.finalEffectiveListIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Conflicts/exclusions", diagnostics.effectiveSelectionDiagnostics?.droppedConflictingIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Active manifest list IDs", diagnostics.activeManifestListIdentifiers.joined(separator: ", ")),
            ("Compiler diagnostics", diagnostics.compilerDiagnosticsSummary ?? "nil"),
            ("Native compiler", diagnostics.nativeCompiler.map { "\($0.name) \($0.version)" } ?? "nil"),
            ("Network shard count", diagnostics.networkShardCount.description),
            ("Native CSS shard count", diagnostics.nativeCSSShardCount.description),
            ("Attached shard count", diagnostics.attachedShardIdentifiers.count.description),
            ("Expected network shards", diagnostics.expectedNetworkShardIdentifiers.joined(separator: ", ")),
            ("Expected native CSS shards", diagnostics.expectedNativeCSSShardIdentifiers.joined(separator: ", ")),
            ("Missing shards", diagnostics.missingShardIdentifiers.joined(separator: ", ")),
            ("Total network rules", diagnostics.totalNetworkRuleCount.description),
            ("Total native CSS rules", diagnostics.totalNativeCSSRuleCount.description),
            ("Largest shard JSON bytes", diagnostics.largestShardJSONByteCount.description),
            ("Peak rebuild memory", debugByteString(diagnostics.latestRebuildMemoryDiagnostics?.peakResidentMemoryBytes)),
            ("Steady rebuild memory", debugByteString(diagnostics.latestRebuildMemoryDiagnostics?.steadyStateResidentMemoryBytes)),
            ("Current process memory", debugByteString(diagnostics.currentProcessResidentMemoryBytes)),
            ("Memory stages", diagnostics.latestRebuildMemoryDiagnostics?.snapshots.map { "\($0.stage.rawValue)=\(debugByteString($0.residentMemoryBytes))" }.joined(separator: ", ") ?? "nil"),
            ("Budget warnings", debugBudgetWarnings.joined(separator: " | ")),
            ("Cap/discard", debugRuleCapString(diagnostics)),
            ("Unsafe native CSS filtered", diagnostics.unsafeNativeCSSFilteredRuleCount.description),
            ("Cosmetic mode", diagnostics.cosmeticMode?.rawValue ?? "nil"),
            ("Enhanced runtime", diagnostics.enhancedRuntimeIsEnabled.description),
            ("Tracking Protection", diagnostics.trackingProtectionModuleEnabled.description),
        ]
    }

    private func debugListRows(_ status: AdblockFilterListUpdateStatus) -> [(String, String)] {
        [
            ("List id", status.listIdentifier),
            ("Category", status.category?.rawValue ?? "nil"),
            ("Selection origin", status.selectionOrigins.map(\.rawValue).joined(separator: ", ")),
            ("Final URL", status.finalURL ?? "nil"),
            ("Last checked", debugDateString(status.lastCheckedDate)),
            ("Last successful download", debugDateString(status.lastSuccessfulDownloadDate)),
            ("HTTP status", status.httpStatus.map(String.init) ?? "nil"),
            ("ETag used", status.eTagUsed ?? "nil"),
            ("ETag saved", status.eTagSaved ?? "nil"),
            ("Last-Modified used", status.lastModifiedUsed ?? "nil"),
            ("Last-Modified saved", status.lastModifiedSaved ?? "nil"),
            ("304 reuse", status.notModifiedReused.description),
            ("Raw file path", status.rawFilePath ?? "nil"),
            ("Raw file exists", status.rawFileExists.description),
            ("Raw bytes", status.rawByteSize.map(String.init) ?? "nil"),
            ("Content hash", status.contentHash ?? "nil"),
            ("Failure stage", status.failureStage?.rawValue ?? "nil"),
            ("Failure reason", status.failureReason ?? "nil"),
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
            ("Attachment assessment", diagnostics.attachmentAssessment),
            ("Attached generation", diagnostics.attachedGenerationId ?? "nil"),
            ("Attached generation IDs", diagnostics.attachedGenerationIds.joined(separator: ", ")),
            ("Uses active generation", diagnostics.tabUsesActiveGeneration.description),
            ("Appears older generation", diagnostics.tabAppearsToUseOlderGeneration.description),
            ("Mixed generation", diagnostics.hasMixedGenerationAttachment.description),
            ("Attached while disabled", diagnostics.attachedWhilePerSiteAdblockDisabled.description),
            ("Native CSS while off", diagnostics.nativeCSSAttachedWhileCosmeticModeOff.description),
            ("Reload for active generation", diagnostics.reloadRequiredForActiveGeneration.description),
            ("Suspected blank page category", diagnostics.suspectedBlankPageCategory),
            ("After attachment memory", debugByteString(diagnostics.attachmentMemorySnapshot?.residentMemoryBytes)),
            ("Active generation", diagnostics.activeGenerationId ?? "nil"),
            ("Selected profile", diagnostics.selectedNativeProfile?.rawValue ?? "nil"),
            ("Active compiled profile", diagnostics.activeCompiledNativeProfile?.rawValue ?? "nil"),
            ("Cosmetic mode", diagnostics.cosmeticMode?.rawValue ?? "nil"),
            ("Expected network shards", diagnostics.expectedNetworkShardIdentifiers.joined(separator: ", ")),
            ("Expected native CSS shards", diagnostics.expectedNativeCSSShardIdentifiers.joined(separator: ", ")),
            ("Actual attached shards", diagnostics.actualAttachedShardIdentifiers.joined(separator: ", ")),
            ("Recorded applied shards", diagnostics.recordedAppliedShardIdentifiers.joined(separator: ", ")),
            ("Attached network shards", diagnostics.attachedNetworkShardIdentifiers.joined(separator: ", ")),
            ("Attached native CSS shards", diagnostics.attachedNativeCSSShardIdentifiers.joined(separator: ", ")),
            ("Missing shards", diagnostics.missingShardIdentifiers.joined(separator: ", ")),
            ("Unexpected old shards", diagnostics.unexpectedOldShardIdentifiers.joined(separator: ", ")),
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
                    Text(debugCompactValue(row.1))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
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
                    debugDiagnosticsTarget.tab?.updateAdblockReloadRequirementForCurrentSite()
                    isRebuilding = false
                }
            } catch {
                await MainActor.run {
                    if let diagnostics = error as? AdblockUpdateDiagnostics {
                        rebuildStatus = "Rebuild failed: \(diagnostics.summary)"
                    } else {
                        rebuildStatus = "Rebuild failed: \(error.localizedDescription)"
                    }
                    isRebuilding = false
                }
            }
        }
    }

    private func installSelectedEmbeddedBundle() {
        guard !isInstallingEmbeddedBundle,
              let profile = selectedEmbeddedBundleProfile
        else { return }
        isInstallingEmbeddedBundle = true
        embeddedBundleInstallStatus = nil
        Task {
            do {
                let manifest = try await adBlockingModule.installEmbeddedAdblockBundle(profileId: profile.id)
                await MainActor.run {
                    if let manifest {
                        embeddedBundleInstallStatus = "Installed \(profile.id). generationSource=\(manifest.generationSource.rawValue); nativeRuleBundleId=\(manifest.nativeRuleBundleId ?? "nil")."
                    } else {
                        embeddedBundleInstallStatus = "No install ran. Enable built-in Adblock before installing."
                    }
                    debugDiagnosticsTarget.tab?.updateAdblockReloadRequirementForCurrentSite()
                    isInstallingEmbeddedBundle = false
                }
            } catch {
                await MainActor.run {
                    if let diagnostics = error as? AdblockUpdateDiagnostics {
                        embeddedBundleInstallStatus = "Install failed: \(diagnostics.summary)"
                    } else {
                        embeddedBundleInstallStatus = "Install failed: \(error.localizedDescription)"
                    }
                    isInstallingEmbeddedBundle = false
                }
            }
        }
    }

    private func resetListsToSelectedProfile() {
        settings.resetListsToSelectedProfile()
        resetListsStatus = "Reset runtime-generated profile lists to \(selectedProfileDisplayName). Embedded bundle selection is unchanged."
    }

    private func debugCompactValue(_ value: String) -> String {
        guard !value.isEmpty else { return "[]" }
        let limit = 240
        guard value.count > limit else { return value }
        let head = value.prefix(120)
        let tail = value.suffix(80)
        return "\(head) ... \(tail) (\(value.count) chars; copy diagnostics for full value)"
    }

    private func copyAdblockDiagnostics() {
        let target = debugDiagnosticsTarget
        let report = adBlockingModule.copyDiagnosticsReport(
            for: target.url,
            currentTabDiagnostics: target.tab?.adblockCurrentTabDiagnostics(),
            targetDescription: target.source,
            requestingURL: currentTab?.url
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        copyDiagnosticsStatus = "Copied \(debugDateString(Date())) for \(target.url?.absoluteString ?? target.source)."
    }

    private func debugDateString(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return Self.debugDateFormatter.string(from: date)
    }

    private func debugRuleCapString(_ diagnostics: SumiAdblockAttachmentDiagnostics) -> String {
        guard let cap = diagnostics.nativeCompilationSummary?.ruleCap else { return "nil" }
        return "hit=\(cap.wasHit) discarded=\(cap.discardedRuleCount)"
    }

    private var debugBudgetWarnings: [String] {
        let diagnostics = debugDiagnostics
        let compiledWarnings = AdblockRebuildBudget.warnings(
            networkRuleCount: diagnostics.totalNetworkRuleCount,
            nativeCSSRuleCount: diagnostics.totalNativeCSSRuleCount,
            shardCount: diagnostics.networkShardCount + diagnostics.nativeCSSShardCount,
            selectionDiagnostics: diagnostics.effectiveSelectionDiagnostics
        )
        if compiledWarnings.isEmpty, diagnostics.generationIsStale {
            return ["Active generation counts may not match the selected lists until rebuild completes."]
        }
        return compiledWarnings
    }

    private func debugByteString(_ bytes: UInt64?) -> String {
        guard let bytes else { return "nil" }
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", mib)
    }

    private func debugByteString(_ bytes: UInt64) -> String {
        debugByteString(Optional(bytes))
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

#if DEBUG
private struct DebugAdblockDiagnosticsTarget {
    let tab: Tab?
    let url: URL?
    let source: String
}
#endif

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
