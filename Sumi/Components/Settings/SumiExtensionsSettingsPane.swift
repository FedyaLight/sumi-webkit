//
//  SumiExtensionsSettingsPane.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SumiExtensionsSettingsPane: View {
    @Environment(\.sumiSettings) private var sumiSettingsModel
    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @State private var busyExtensionIDs: Set<String> = []
    @State private var extensionPendingRemoval: InstalledExtension?
    @State private var extensionOperationTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        @Bindable var sumiSettings = sumiSettingsModel

        VStack(alignment: .leading, spacing: 16) {
            Picker("Section", selection: $sumiSettings.extensionsSettingsSubPane) {
                ForEach(SumiExtensionsSettingsSubPane.allCases, id: \.self) { segment in
                    Text(segment.segmentTitle).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Extensions and userscripts")

            switch sumiSettings.extensionsSettingsSubPane {
            case .extensions:
                SumiSettingsModuleToggleGate(descriptor: .extensions) {
                    extensionsManagerBody
                        .onDisappear {
                            clearExtensionPaneState()
                        }
                }
            case .userScripts:
                SumiSettingsModuleToggleGate(descriptor: .userScripts) {
                    if let manager = browserManager.userscriptsModule.managerIfEnabled() {
                        SumiScriptsManagerView(manager: manager)
                    }
                }
            }
        }
        .onDisappear {
            clearExtensionPaneState()
        }
        .onChange(of: sumiSettings.extensionsSettingsSubPane) { _, subPane in
            if subPane != .extensions {
                clearExtensionPaneState()
            }
        }
        .confirmationDialog(
            "Remove Extension?",
            isPresented: extensionRemovalBinding
        ) {
            Button("Remove", role: .destructive) {
                if let extensionPendingRemoval {
                    uninstallExtension(extensionPendingRemoval)
                }
                extensionPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                extensionPendingRemoval = nil
            }
        } message: {
            Text(extensionPendingRemoval?.name ?? "")
        }
    }

    @ViewBuilder
    private var extensionsManagerBody: some View {
        if browserManager.extensionsModule.managerIfEnabled() != nil {
            let installedExtensions = extensionSurfaceStore.installedExtensions
            extensionsBody(
                installedExtensions: installedExtensions,
                siteAccessPoliciesByExtensionID:
                    extensionSurfaceStore.siteAccessPoliciesByExtensionID
            )
            .task(
                id: ExtensionsSiteAccessPolicyRefreshKey(
                    profileId: browserManager.currentProfile?.id,
                    extensionIds: installedExtensions.map(\.id)
                )
            ) {
                extensionSurfaceStore.refreshSiteAccessPolicies(
                    profileId: browserManager.currentProfile?.id
                )
            }
        } else {
            Text("Enable the Extensions module to manage installed extensions.")
                .foregroundStyle(.secondary)
        }
    }

    private var extensionRemovalBinding: Binding<Bool> {
        Binding(
            get: { extensionPendingRemoval != nil },
            set: { isPresented in
                if !isPresented { extensionPendingRemoval = nil }
            }
        )
    }

    @ViewBuilder
    private func extensionsBody(
        installedExtensions: [InstalledExtension],
        siteAccessPoliciesByExtensionID: [String: SafariExtensionSiteAccessPolicy]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Installed Extensions",
                subtitle: installedExtensions.isEmpty
                    ? "No extensions are installed"
                    : "Safari app extensions and unpacked developer extensions enabled in Sumi"
            ) {
                if installedExtensions.isEmpty {
                    Text("Sumi did not find any installed extensions in its local runtime store.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(installedExtensions, id: \.id) { ext in
                            ExtensionCatalogRow(
                                extensionRecord: ext,
                                siteAccessPolicy: siteAccessPoliciesByExtensionID[ext.id],
                                isBusy: busyExtensionIDs.contains(ext.id),
                                onToggleEnabled: {
                                    toggleExtension(ext)
                                },
                                onDefaultSiteAccessChanged: { access in
                                    browserManager.extensionsModule.setDefaultSiteAccess(
                                        access,
                                        extensionId: ext.id,
                                        profileId: browserManager.currentProfile?.id
                                    )
                                },
                                onPrivateAccessChanged: { isAllowed in
                                    browserManager.extensionsModule.setPrivateBrowsingAccess(
                                        isAllowed,
                                        extensionId: ext.id,
                                        profileId: browserManager.currentProfile?.id
                                    )
                                },
                                onConfiguredSiteAccessChanged: { matchPattern, access in
                                    browserManager.extensionsModule.setConfiguredSiteAccess(
                                        access,
                                        extensionId: ext.id,
                                        profileId: browserManager.currentProfile?.id,
                                        matchPatternString: matchPattern
                                    )
                                },
                                onOpenOptions: {
                                    Task { @MainActor in
                                        await browserManager.extensionsModule.openOptionsPage(
                                            extensionId: ext.id,
                                            profileId: browserManager.currentProfile?.id
                                        )
                                    }
                                },
                                onUninstall: {
                                    extensionPendingRemoval = ext
                                }
                            )
                        }
                    }
                }
            }

            SettingsSection(
                title: "Safari App Extensions",
                subtitle: "Discover Safari Web Extensions bundled in installed macOS apps"
            ) {
                SafariExtensionImportCandidatesSection(
                    installedExtensions: installedExtensions,
                    onStatus: { _ in }
                )
            }
        }
    }

    private func toggleExtension(_ extensionRecord: InstalledExtension) {
        extensionOperationTasks[extensionRecord.id]?.cancel()
        busyExtensionIDs.insert(extensionRecord.id)
        extensionOperationTasks[extensionRecord.id] = Task { @MainActor in
            do {
                if extensionRecord.isEnabled {
                    try await browserManager.extensionsModule.disableExtension(
                        extensionRecord.id
                    )
                } else {
                    _ = try await browserManager.extensionsModule.enableExtension(
                        extensionRecord.id
                    )
                }
            } catch {}
            guard !Task.isCancelled else { return }
            busyExtensionIDs.remove(extensionRecord.id)
            extensionOperationTasks[extensionRecord.id] = nil
        }
    }

    private func uninstallExtension(_ extensionRecord: InstalledExtension) {
        extensionOperationTasks[extensionRecord.id]?.cancel()
        busyExtensionIDs.insert(extensionRecord.id)
        extensionOperationTasks[extensionRecord.id] = Task { @MainActor in
            do {
                try await browserManager.extensionsModule.uninstallExtension(
                    extensionRecord.id
                )
            } catch {}
            guard !Task.isCancelled else { return }
            busyExtensionIDs.remove(extensionRecord.id)
            extensionOperationTasks[extensionRecord.id] = nil
        }
    }

    private func cancelExtensionPaneTasks() {
        extensionOperationTasks.values.forEach { $0.cancel() }
        extensionOperationTasks.removeAll()
        busyExtensionIDs.removeAll()
    }

    private func clearExtensionPaneState() {
        cancelExtensionPaneTasks()
        extensionSurfaceStore.refreshSiteAccessPolicies(profileId: nil)
    }
}

private struct ExtensionsSiteAccessPolicyRefreshKey: Hashable {
    let profileId: UUID?
    let extensionIds: [String]
}

private struct ExtensionCatalogRow: View {
    let extensionRecord: InstalledExtension
    let siteAccessPolicy: SafariExtensionSiteAccessPolicy?
    let isBusy: Bool
    let onToggleEnabled: () -> Void
    let onDefaultSiteAccessChanged: (SafariExtensionSiteAccessLevel) -> Void
    let onPrivateAccessChanged: (Bool) -> Void
    let onConfiguredSiteAccessChanged: (String, SafariExtensionSiteAccessLevel) -> Void
    let onOpenOptions: () -> Void
    let onUninstall: () -> Void

    @State private var isEnabled = false
    @State private var defaultSiteAccess: SafariExtensionSiteAccessLevel = .allow
    @State private var privateAccessAllowed = false
    @State private var isDetailsPresented = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            extensionIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(extensionRecord.name)
                        .font(.headline)
                        .lineLimit(1)

                    if extensionRecord.legacyManifestMayUseMoreEnergy {
                        Image(systemName: "battery.100percent.bolt")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.orange)
                            .help(InstalledExtensionRecord.legacyManifestWarningTooltip)
                            .accessibilityLabel(InstalledExtensionRecord.legacyManifestWarningTooltip)
                    }
                }

                Text(rowSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(isBusy)
                    .help(extensionRecord.isEnabled ? "Disable extension" : "Enable extension")
                    .onChange(of: isEnabled) { oldValue, newValue in
                        guard oldValue != newValue, newValue != extensionRecord.isEnabled else {
                            return
                        }
                        onToggleEnabled()
                    }

                Button {
                    isDetailsPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .help("Extension information and permissions")
                .popover(isPresented: $isDetailsPresented, arrowEdge: .trailing) {
                    ExtensionCatalogDetailsPopover(
                        extensionRecord: extensionRecord,
                        siteAccessPolicy: siteAccessPolicy,
                        isBusy: isBusy,
                        defaultSiteAccess: $defaultSiteAccess,
                        privateAccessAllowed: $privateAccessAllowed,
                        onConfiguredSiteAccessChanged: onConfiguredSiteAccessChanged,
                        onOpenOptions: onOpenOptions
                    )
                    .frame(width: 430)
                    .padding(16)
                }

                Button(role: .destructive) {
                    onUninstall()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .regular))
                }
                .buttonStyle(NavButtonStyle(size: .small))
                .disabled(isBusy)
                .help("Remove extension")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear {
            isEnabled = extensionRecord.isEnabled
            syncSiteAccessState()
        }
        .onChange(of: extensionRecord.isEnabled) { _, newValue in
            isEnabled = newValue
        }
        .onChange(of: siteAccessPolicy) { _, _ in
            syncSiteAccessState()
        }
        .onChange(of: defaultSiteAccess) { oldValue, newValue in
            guard oldValue != newValue,
                  newValue != siteAccessPolicy?.defaultAccess
            else { return }
            onDefaultSiteAccessChanged(newValue)
        }
        .onChange(of: privateAccessAllowed) { oldValue, newValue in
            guard oldValue != newValue,
                  newValue != siteAccessPolicy?.privateAccessAllowed
            else { return }
            onPrivateAccessChanged(newValue)
        }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconPath = ExtensionUtils.iconPath(for: extensionRecord),
           let image = NSImage(contentsOfFile: iconPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.secondary)
        }
    }

    private var rowSummary: String {
        "Version \(extensionRecord.version)"
    }

    private func syncSiteAccessState() {
        defaultSiteAccess = siteAccessPolicy?.defaultAccess ?? .allow
        privateAccessAllowed = siteAccessPolicy?.privateAccessAllowed ?? false
    }
}

private struct ExtensionCatalogDetailsPopover: View {
    let extensionRecord: InstalledExtension
    let siteAccessPolicy: SafariExtensionSiteAccessPolicy?
    let isBusy: Bool
    @Binding var defaultSiteAccess: SafariExtensionSiteAccessLevel
    @Binding var privateAccessAllowed: Bool
    let onConfiguredSiteAccessChanged: (String, SafariExtensionSiteAccessLevel) -> Void
    let onOpenOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if showsWarnings {
                detailSection("Warnings") {
                    VStack(alignment: .leading, spacing: 8) {
                        if extensionRecord.activationSummary.broadScope {
                            warningRow(
                                systemImage: "hand.raised.fill",
                                text: "Can read and change website data on allowed websites."
                            )
                        }
                        if extensionRecord.legacyManifestMayUseMoreEnergy {
                            warningRow(
                                systemImage: "battery.100percent.bolt",
                                text: InstalledExtensionRecord.legacyManifestWarningTooltip
                            )
                        }
                    }
                }
            }

            if showsWebsiteAccessControls {
                detailSection("Website Access") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("Other Websites")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: $defaultSiteAccess) {
                                ForEach(SafariExtensionSiteAccessLevel.allCases) { access in
                                    Text(access.title).tag(access)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 112)
                            .disabled(isBusy)
                        }

                        if configuredSiteRules.isEmpty == false {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Configured Websites")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(configuredSiteRules) { rule in
                                    HStack(spacing: 10) {
                                        Text(displayName(for: rule.matchPattern))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Picker(
                                            "",
                                            selection: configuredSiteAccessBinding(for: rule)
                                        ) {
                                            ForEach(SafariExtensionSiteAccessLevel.allCases) {
                                                access in
                                                Text(access.title).tag(access)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .frame(width: 112)
                                        .disabled(isBusy)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if extensionRecord.incognitoMode.allowsPrivateAccess {
                detailSection("Private Access") {
                    Toggle("Allow in Private Browsing", isOn: $privateAccessAllowed)
                        .toggleStyle(.checkbox)
                        .disabled(isBusy)
                }
            }

            detailSection("Shortcuts") {
                if commandRows.isEmpty {
                    Text("No keyboard shortcuts declared.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(commandRows) { command in
                            HStack(spacing: 10) {
                                Text(command.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(command.shortcut ?? "Not set")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            detailSection("Settings") {
                if extensionRecord.hasOptionsPage {
                    Button("Open Extension Settings") {
                        onOpenOptions()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || extensionRecord.isEnabled == false)
                } else {
                    Text("No extension settings page.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let iconPath = ExtensionUtils.iconPath(for: extensionRecord),
                   let image = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(extensionRecord.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Version \(extensionRecord.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsWarnings: Bool {
        extensionRecord.activationSummary.broadScope
            || extensionRecord.legacyManifestMayUseMoreEnergy
    }

    private var showsWebsiteAccessControls: Bool {
        extensionRecord.activationSummary.matchPatternStrings.isEmpty == false
            || optionalHostPermissionStrings.isEmpty == false
            || optionalPermissionHostPatternStrings.isEmpty == false
    }

    private var optionalHostPermissionStrings: [String] {
        extensionRecord.manifest["optional_host_permissions"] as? [String] ?? []
    }

    private var optionalPermissionHostPatternStrings: [String] {
        (extensionRecord.manifest["optional_permissions"] as? [String] ?? [])
            .filter {
                $0 == "<all_urls>"
                    || $0.hasPrefix("http://")
                    || $0.hasPrefix("https://")
                    || $0.hasPrefix("*://")
            }
    }

    private var configuredSiteRules: [SafariExtensionSiteAccessRule] {
        siteAccessPolicy?.siteRules ?? []
    }

    private var commandRows: [ExtensionCommandSummary] {
        guard let commands = extensionRecord.manifest["commands"] as? [String: Any] else {
            return []
        }

        return commands.compactMap { key, value in
            guard let command = value as? [String: Any] else { return nil }
            let title =
                (command["description"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? humanizedCommandName(key)
            let shortcut = shortcutString(from: command["suggested_key"])
            return ExtensionCommandSummary(
                id: key,
                title: title.isEmpty ? humanizedCommandName(key) : title,
                shortcut: shortcut
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func configuredSiteAccessBinding(
        for rule: SafariExtensionSiteAccessRule
    ) -> Binding<SafariExtensionSiteAccessLevel> {
        Binding(
            get: {
                configuredSiteRules
                    .first { $0.matchPattern == rule.matchPattern }?
                    .access ?? rule.access
            },
            set: { access in
                guard access != rule.access else { return }
                onConfiguredSiteAccessChanged(rule.matchPattern, access)
            }
        )
    }

    private func displayName(for matchPattern: String) -> String {
        guard let url = URL(string: matchPattern),
              let host = url.host,
              host.isEmpty == false
        else {
            return matchPattern
        }
        return host
    }

    private func shortcutString(from value: Any?) -> String? {
        if let raw = value as? String {
            return raw.isEmpty ? nil : raw
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        let candidates = ["mac", "default", "chromeos", "linux", "windows"]
        for key in candidates {
            if let raw = dictionary[key] as? String,
               raw.isEmpty == false {
                return raw
            }
        }
        return nil
    }

    private func humanizedCommandName(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func warningRow(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
        }
        .font(.caption)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExtensionCommandSummary: Identifiable {
    let id: String
    let title: String
    let shortcut: String?
}
