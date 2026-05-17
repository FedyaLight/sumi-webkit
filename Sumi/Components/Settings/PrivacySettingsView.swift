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
    @Environment(\.sumiProtectionCoordinator) private var protectionCoordinator
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

                    AdblockProtectionSettingsView(
                        coordinator: protectionCoordinator,
                        browserManager: browserManager,
                        windowState: windowState,
                        currentTab: currentTab
                    )



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

private struct AdblockProtectionSettingsView: View {
    let coordinator: SumiProtectionCoordinator
    let browserManager: BrowserManager
    let windowState: BrowserWindowState?
    let currentTab: Tab?
    @ObservedObject private var settings: SumiProtectionSettings
    @State private var overrideStatus: String?
    @State private var applyStatus: String?
    @State private var isApplying = false
    #if DEBUG
    @State private var copyDiagnosticsStatus: String?
    #endif

    init(
        coordinator: SumiProtectionCoordinator,
        browserManager: BrowserManager,
        windowState: BrowserWindowState?,
        currentTab: Tab?
    ) {
        self.coordinator = coordinator
        self.browserManager = browserManager
        self.windowState = windowState
        self.currentTab = currentTab
        _settings = ObservedObject(wrappedValue: coordinator.settings)
    }

    var body: some View {
        SettingsSection(
            title: "Adblock & Protection",
            subtitle: "One native protection plan controls tracker blocking, native ad blocking, and per-site disable."
        ) {
            SettingsRow(
                title: "Level",
                subtitle: settings.level.detail
            ) {
                Picker("", selection: levelBinding) {
                    ForEach(SumiProtectionLevel.allCases) { level in
                        Text(level.displayTitle).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }


            SettingsRow(
                title: "Apply selected protection level",
                subtitle: applyRowSubtitle
            ) {
                Button {
                    applySelectedLevel()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Apply")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || !coordinator.applyNeeded)
            }

            SettingsRow(
                title: "Applied level",
                subtitle: appliedLevelSubtitle
            ) {
                Text(settings.appliedLevel.displayTitle)
                    .font(.callout)
                    .foregroundStyle(coordinator.applyNeeded ? Color.orange : Color.secondary)
            }

            SettingsRow(
                title: "Current page level",
                subtitle: currentPageLevelSubtitle
            ) {
                Text(currentPagePlan.effectiveLevel.displayTitle)
                    .font(.callout)
                    .foregroundStyle(currentPagePlan.effectiveLevel == settings.appliedLevel ? Color.secondary : Color.orange)
            }

            SettingsRow(
                title: "Current site",
                subtitle: currentSiteSubtitle
            ) {
                Button(currentSiteButtonTitle) {
                    toggleCurrentSiteProtection()
                }
                .buttonStyle(.bordered)
                .disabled(currentTab == nil || currentPagePlan.siteHost == nil || settings.appliedLevel == .off)
            }

            if let overrideStatus {
                Text(overrideStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            SettingsDivider()
            Text("DEBUG Unified Protection Diagnostics")
                .font(.subheadline)
                .fontWeight(.medium)

            SettingsRow(
                title: "Copy Diagnostics",
                subtitle: copyDiagnosticsStatus ?? "Copies the unified plan, active groups, bundle, overlap, dedupe, and target-tab attachment state."
            ) {
                Button("Copy") {
                    copyUnifiedProtectionDiagnostics()
                }
                .buttonStyle(.bordered)
            }

            debugKeyValueGrid(rows: debugProtectionRows)
            #endif
        }
    }

    private var levelBinding: Binding<SumiProtectionLevel> {
        Binding(
            get: { settings.level },
            set: { level in
                coordinator.setLevel(level)
                applyStatus = "Selection saved. Apply is required before eligible web tabs use \(level.displayTitle)."
            }
        )
    }

    private var currentPagePlan: SumiProtectionRulePlan {
        coordinator.cachedRulePlan(for: currentTab?.url, profileId: currentTab?.resolveProfile()?.id)
    }

    private var diagnosticsPlan: SumiProtectionRulePlan {
        coordinator.cachedRulePlan(for: diagnosticsTarget.url, profileId: diagnosticsTarget.tab?.resolveProfile()?.id)
    }

    private var globalDiagnostics: SumiProtectionGlobalDiagnostics {
        coordinator.globalDiagnostics()
    }

    private var applyRowSubtitle: String {
        if let applyStatus {
            return applyStatus
        }
        if let error = globalDiagnostics.lastApplyError {
            return error
        }
        if coordinator.applyNeeded {
            return "Selection saved. Apply to activate \(settings.level.displayTitle) and mark changed web tabs reload-required."
        }
        return globalDiagnostics.lastApplySummary ?? "Selected level is already applied."
    }

    private var appliedLevelSubtitle: String {
        if coordinator.applyNeeded {
            return "Selected \(settings.level.displayTitle) is not active yet."
        }
        return "This is the level used to build eligible page attachment plans."
    }

    private var currentPageLevelSubtitle: String {
        if let reason = currentPagePlan.ineligibleSurfaceReason {
            return reason
        }
        if !currentPagePlan.planningErrors.isEmpty {
            return currentPagePlan.planningErrors.joined(separator: " ")
        }
        if currentPagePlan.bundleProfileId != nil {
            return "Bundle source: \(currentPagePlan.bundleSource?.rawValue ?? "unknown")."
        }
        return "Native WebKit rule lists only; no Adblock runtime script is enabled by this level."
    }

    private var currentSiteSubtitle: String {
        guard let host = currentPagePlan.siteHost else {
            return "Open an http or https tab to change site protection."
        }
        if settings.appliedLevel == .off {
            return "Applied global level is Off."
        }
        if currentPagePlan.siteOverride == .disabled {
            return "Protection off for this site: \(host). Reload required for existing pages."
        }
        return "Protection follows the applied \(settings.appliedLevel.displayTitle) level for \(host)."
    }

    private var currentSiteButtonTitle: String {
        currentPagePlan.siteOverride == .disabled
            ? "Use Global Level"
            : "Turn Off for Site"
    }

    private func toggleCurrentSiteProtection() {
        guard let tab = currentTab else { return }
        let nextOverride: SumiAdblockSiteOverride = currentPagePlan.siteOverride == .disabled
            ? .inherit
            : .disabled
        coordinator.setSiteOverride(nextOverride, for: tab.url)
        tab.markProtectionReloadRequiredIfNeeded(afterChangingPolicyFor: tab.url)
        overrideStatus = nextOverride == .disabled
            ? "Protection will be off for this site after reload."
            : "This site will use the global level after reload."
    }

    private func applySelectedLevel() {
        guard !isApplying else { return }
        isApplying = true
        applyStatus = nil
        Task {
            do {
                let outcome = try await coordinator.applySelectedLevel()
                let markedTabs = browserManager.markProtectionReloadRequiredForEligibleNormalWebTabs()
                coordinator.recordReloadMarkingAfterApply(tabCount: markedTabs)
                await MainActor.run {
                    applyStatus = coordinator.globalDiagnostics().lastApplySummary ?? outcome.summary
                    isApplying = false
                }
            } catch {
                await MainActor.run {
                    applyStatus = error.localizedDescription
                    isApplying = false
                }
            }
        }
    }

    private var diagnosticsTarget: DebugProtectionDiagnosticsTarget {
        let currentEligibility = coordinator.surfaceEligibility(for: currentTab?.url)
        if let currentTab, currentEligibility.isEligible {
            return DebugProtectionDiagnosticsTarget(
                tab: currentTab,
                url: currentTab.url,
                source: "current tab"
            )
        }

        #if DEBUG
        if let fallback = browserManager.lastActiveProtectionEligibleNormalWebTab(
            in: windowState,
            excluding: currentTab
        ) {
            let source: String
            if let reason = currentEligibility.ineligibleReason {
                source = "last eligible web tab (current tab ineligible: \(reason))"
            } else {
                source = "last eligible web tab"
            }
            return DebugProtectionDiagnosticsTarget(
                tab: fallback,
                url: fallback.url,
                source: source
            )
        }
        #endif

        return DebugProtectionDiagnosticsTarget(
            tab: currentTab,
            url: currentTab?.url,
            source: currentEligibility.ineligibleReason.map {
                "current tab (ineligible: \($0))"
            } ?? "current tab"
        )
    }

    #if DEBUG
    private var debugProtectionRows: [(String, String)] {
        let global = globalDiagnostics
        let plan = diagnosticsPlan
        let contentBlockingSummary = diagnosticsTarget.tab?
            .existingWebView?
            .configuration
            .userContentController
            .sumiNormalTabUserContentController?
            .contentBlockingAssetSummary
        let actualAttachedIdentifiers = contentBlockingSummary?.globalRuleListIdentifiers ?? []
        let expectedSet = Set(plan.expectedRuleListIdentifiers)
        let actualSet = Set(actualAttachedIdentifiers)
        let missingAfterAttachment = plan.expectedRuleListIdentifiers.filter { !actualSet.contains($0) }
        let unexpectedOldIdentifiers = actualAttachedIdentifiers.filter {
            !expectedSet.contains($0)
                && ($0.hasPrefix("sumi.adblock.")
                    || $0.hasPrefix("sumi.tracking.")
                    || $0 == "SumiTrackingProtectionTrackerDataSet")
        }
        return [
            ("GLOBAL selected protection level", global.selectedProtectionLevel.rawValue),
            ("GLOBAL applied protection level", global.appliedProtectionLevel.rawValue),
            ("GLOBAL apply needed", global.applyNeeded.description),
            ("GLOBAL last apply summary", global.lastApplySummary ?? "nil"),
            ("GLOBAL last apply error", global.lastApplyError ?? "nil"),
            ("GLOBAL generation source", global.generationSource?.rawValue ?? "nil"),
            ("GLOBAL native bundle id", global.nativeRuleBundleId ?? "nil"),
            ("GLOBAL bundle profile id", global.bundleProfileId ?? "nil"),
            ("GLOBAL required bundle profile", global.requiredBundleProfileId ?? "nil"),
            ("GLOBAL prepared bundle available", global.preparedBundleAvailable.description),
            ("GLOBAL prepared bundle source", global.preparedBundleSource?.rawValue ?? "nil"),
            ("GLOBAL searched bundle paths", global.searchedBundlePaths.map { "\($0.source.rawValue): exists=\($0.exists) path=\($0.path) rejected=\($0.rejectionReason ?? "nil")" }.joined(separator: " | ")),
            ("GLOBAL active generation", global.activeGenerationId ?? "nil"),
            ("GLOBAL groups available", global.globalGroupsAvailable.map(\.rawValue).joined(separator: ", ")),
            ("GLOBAL tracking source available", global.trackingSourceAvailable.description),
            ("GLOBAL adblock bundle available", global.adblockBundleAvailable.description),
            ("GLOBAL strict Off active", global.strictOffActive.description),
            ("Diagnostics target", diagnosticsTarget.source),
            ("Diagnostics URL", diagnosticsTarget.url?.absoluteString ?? "nil"),
            ("PAGE requested level", plan.requestedLevel.rawValue),
            ("Effective level", plan.effectiveLevel.rawValue),
            ("Desired groups", plan.requestedLevel.requestedGroups.map(\.rawValue).joined(separator: ", ")),
            ("Active groups", plan.activeGroups.map(\.rawValue).joined(separator: ", ")),
            ("Inactive groups", plan.inactiveGroups.map(\.rawValue).joined(separator: ", ")),
            ("Per-site protection", plan.sitePolicyAllowsProtection.description),
            ("Site override", plan.siteOverride.rawValue),
            ("Generation source", plan.bundleSource?.rawValue ?? "nil"),
            ("Native bundle id", plan.nativeRuleBundleId ?? "nil"),
            ("Bundle profile id", plan.bundleProfileId ?? "nil"),
            ("Required bundle profile", plan.requiredBundleProfileId ?? "nil"),
            ("Active generation", plan.activeGenerationId ?? "nil"),
            ("Previous generation", plan.previousGenerationId ?? "nil"),
            ("Previous retained", plan.previousGenerationRetained.description),
            ("Tracking active", plan.trackingGroupActive.description),
            ("Adblock active", plan.adblockGroupActive.description),
            ("Rule counts", debugCounts(plan.ruleCountsByGroup)),
            ("Shard counts", debugCounts(plan.shardCountsByGroup)),
            ("Dedupe", plan.dedupeSummary.reportLine),
            ("Overlap", plan.overlapSummary.reportLine),
            ("Expected identifiers", plan.expectedRuleListIdentifiers.joined(separator: ", ")),
            ("Lookup succeeded identifiers", contentBlockingSummary?.lookupSucceededIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Lookup failed identifiers", contentBlockingSummary?.lookupFailedIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Added identifiers", contentBlockingSummary?.addedToUserContentControllerIdentifiers.joined(separator: ", ") ?? "nil"),
            ("Actual attached identifiers", actualAttachedIdentifiers.joined(separator: ", ")),
            ("Missing after attachment", missingAfterAttachment.joined(separator: ", ")),
            ("Unexpected old identifiers", unexpectedOldIdentifiers.joined(separator: ", ")),
            ("Applied generation", diagnosticsTarget.tab?.protectionAppliedAttachmentState?.activeGenerationId ?? "nil"),
            ("Applied groups", diagnosticsTarget.tab?.protectionAppliedAttachmentState?.activeGroups.map(\.rawValue).joined(separator: ", ") ?? "nil"),
            ("Ineligible surface", plan.ineligibleSurfaceReason ?? "nil"),
            ("Planning errors", plan.planningErrors.joined(separator: " | ")),
        ]
    }

    private func copyUnifiedProtectionDiagnostics() {
        let target = diagnosticsTarget
        let report = coordinator.copyDiagnosticsReport(
            for: target.url,
            currentTabDiagnostics: target.tab?.protectionCurrentTabDiagnostics(),
            targetDescription: target.source,
            requestingURL: currentTab?.url
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        copyDiagnosticsStatus = "Copied \(debugDateString(Date())) for \(target.url?.absoluteString ?? target.source)."
    }

    private func debugCounts(_ counts: [SumiProtectionGroupKind: Int]) -> String {
        SumiProtectionGroupKind.allCases
            .compactMap { group in
                counts[group].map { "\(group.rawValue)=\($0)" }
            }
            .joined(separator: ", ")
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

    private func debugCompactValue(_ value: String) -> String {
        guard !value.isEmpty else { return "[]" }
        let limit = 240
        guard value.count > limit else { return value }
        let head = value.prefix(120)
        let tail = value.suffix(80)
        return "\(head) ... \(tail) (\(value.count) chars; copy diagnostics for full value)"
    }

    private func debugDateString(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return Self.debugDateFormatter.string(from: date)
    }

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
    #endif
}

private struct DebugProtectionDiagnosticsTarget {
    let tab: Tab?
    let url: URL?
    let source: String
}
