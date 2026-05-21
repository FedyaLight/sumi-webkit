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
    @ObservedObject private var bundleUpdateStatus: SumiProtectionBundleUpdateStatusStore
    @State private var isApplying = false
    @State private var isUpdatingBundles = false
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
        _bundleUpdateStatus = ObservedObject(wrappedValue: coordinator.bundleUpdateStatusStore)
    }

    @ViewBuilder
    var body: some View {
        #if DEBUG
        protectionSettingsSection
            .contextMenu {
                debugDiagnosticsContextMenu
            }
        #else
        protectionSettingsSection
        #endif
    }

    private var protectionSettingsSection: some View {
        SettingsSection(title: "Adblock & Protection") {
            VStack(alignment: .leading, spacing: 12) {
                levelControls

                if settings.browserRestartRequired {
                    restartRequiredWarning
                }

                SettingsDivider()

                lastUpdateRow
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(SumiProtectionLevel.allCases) { level in
                    levelOptionButton(for: level)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Text(applyHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Button {
                    applySelectedLevel()
                } label: {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 44)
                    } else {
                        Text("Apply")
                            .frame(minWidth: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isApplying || !coordinator.applyNeeded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelOptionButton(for level: SumiProtectionLevel) -> some View {
        let isSelected = settings.level == level
        return Button {
            levelBinding.wrappedValue = level
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    Text(level.displayTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                        .accessibilityHidden(true)
                }

                Text(levelSubtitle(for: level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.72)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.58)
                            : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(level.displayTitle), \(levelSubtitle(for: level))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var lastUpdateRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last update")
                    .font(.body)

                Text(lastUpdateText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let lastUpdateErrorText {
                    Text(lastUpdateErrorText)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var applyHelperText: String {
        if isApplying {
            return "Applying..."
        }
        if coordinator.applyNeeded {
            return "Apply to use this level."
        }
        return "Applied."
    }

    private func levelSubtitle(for level: SumiProtectionLevel) -> String {
        switch level {
        case .off:
            return "No blocking"
        case .protection:
            return "Blocks known trackers"
        case .adblock:
            return "Blocks trackers and ads"
        }
    }

    private func applySelectedLevel() {
        guard !isApplying else { return }
        isApplying = true
        Task {
            do {
                _ = try await coordinator.applySelectedLevel()
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
                _ = try await coordinator.updatePreparedBundlesManually()
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
    private var debugDiagnosticsContextMenu: some View {
        Button("Copy Protection Diagnostics") {
            copyUnifiedProtectionDiagnostics()
        }
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

private struct DebugProtectionDiagnosticsTarget {
    let tab: Tab?
    let url: URL?
    let source: String
}
