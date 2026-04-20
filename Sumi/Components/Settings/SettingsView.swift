//
//  SettingsView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

enum SettingsViewStateDeferral {
    static func schedule(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            mutation()
        }
    }
}

// MARK: - Settings Root (Native macOS Settings)
struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) var sumiSettings

    var body: some View {
        SettingsContent(sumiSettings: sumiSettings, browserManager: browserManager)
    }
}

private struct SettingsContent: View {
    @Bindable var sumiSettings: SumiSettingsService
    @ObservedObject var browserManager: BrowserManager

    var body: some View {
        SumiSettingsTabRootView(
            browserManager: browserManager,
            windowState: nil
        )
    }
}

/// Profiles + sidebar behavior (also used in the in-tab settings surface).
struct SumiProfilesSettingsPane: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfilesSettingsView()

            SettingsSectionCard(
                title: "Sumi Sidebar",
                subtitle: "Single-window Sumi behavior for spaces, launchers, and glance"
            ) {
                @Bindable var settings = sumiSettings

                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Enable compact spaces", isOn: $settings.sidebarCompactSpaces)
                    Toggle("Enable glance", isOn: $settings.glanceEnabled)
                    Toggle("Show essentials unload indicator", isOn: $settings.showEssentialsUnloadIndicator)

                    Picker("Glance trigger", selection: $settings.glanceActivationMethod) {
                        ForEach(GlanceActivationMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    Picker("Pinned launcher style", selection: $settings.pinnedTabsLook) {
                        ForEach(PinnedTabsConfiguration.allCases) { configuration in
                            Text(configuration.name).tag(configuration)
                        }
                    }

                    Button("Edit Current Space Theme…") {
                        browserManager.showGradientEditor()
                    }
                    .disabled(browserManager.tabManager.currentSpace == nil)
                }
            }
        }
    }
}

struct SumiDataRecoverySettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionCard(
                title: "Export & Recovery",
                subtitle: "Sumi keeps local SwiftData snapshots and backup directories for recovery"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Reveal Sumi Data Folder") {
                        guard let support = FileManager.default.urls(
                            for: .applicationSupportDirectory,
                            in: .userDomainMask
                        ).first else { return }
                        let bundleId = SumiAppIdentity.runtimeBundleIdentifier
                        let target = support.appendingPathComponent(bundleId, isDirectory: true)
                        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }
                    .buttonStyle(.bordered)

                    Text("Direct profile export is still limited, but Sumi’s runtime store and backups now live in their own app-support path.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SumiExtensionsSettingsPane: View {
    @Environment(\.sumiSettings) private var sumiSettingsModel
    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @State private var discoveredSafariExtensions: [SafariExtensionInfo] = []
    @State private var isDiscoveringSafariExtensions = false
    @State private var busyExtensionIDs: Set<String> = []
    @State private var statusMessage: String?
    @State private var discoveryTask: Task<Void, Never>?
    @State private var extensionOperationTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        @Bindable var sumiSettings = sumiSettingsModel
        let installedExtensions = extensionSurfaceStore.installedExtensions

        VStack(alignment: .leading, spacing: 16) {
            Picker("Section", selection: $sumiSettings.extensionsSettingsSubPane) {
                ForEach(SumiExtensionsSettingsSubPane.allCases, id: \.self) { segment in
                    Text(segment.segmentTitle).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Extensions and userscripts")

            switch sumiSettings.extensionsSettingsSubPane {
            case .safariExtensions:
                safariExtensionsBody(installedExtensions: installedExtensions)
                    .task {
                        if discoveredSafariExtensions.isEmpty {
                            discoverSafariExtensions()
                        }
                    }
            case .userScripts:
                SumiScriptsManagerView(manager: browserManager.sumiScriptsManager)
            }
        }
        .onDisappear {
            cancelExtensionPaneTasks()
        }
        .onChange(of: sumiSettings.extensionsSettingsSubPane) { _, subPane in
            if subPane != .safariExtensions {
                cancelExtensionPaneTasks()
            }
        }
    }

    @ViewBuilder
    private func safariExtensionsBody(installedExtensions: [InstalledExtension]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionCard(
                title: "Extensions",
                subtitle: browserManager.extensionManager.extensionsLoaded
                    ? "Sumi is using the rebuilt Safari/WebExtension backend"
                    : "Sumi is loading installed Safari extensions"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Install Extension…") {
                            browserManager.showExtensionInstallDialog()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(
                            isDiscoveringSafariExtensions
                                ? "Discovering…"
                                : "Discover Safari Extensions"
                        ) {
                            discoverSafariExtensions()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDiscoveringSafariExtensions)
                    }

                    Text(browserManager.extensionManager.isExtensionSupportAvailable
                        ? "Safari extensions can be installed from `.app`, `.appex`, or unpacked directories with a `manifest.json`. Chromium and Mozilla direct runtimes remain intentionally disabled."
                        : "Safari Web Extensions require macOS 15.5 or newer in this Sumi build."
                    )
                        .foregroundStyle(.secondary)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSectionCard(
                title: "Installed Extensions",
                subtitle: installedExtensions.isEmpty
                    ? "No Safari extensions are installed yet"
                    : "Manage enabled state and uninstall installed Safari extensions"
            ) {
                if installedExtensions.isEmpty {
                    Text("Sumi did not find any installed Safari extensions in its local runtime store.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(installedExtensions, id: \.id) { ext in
                            ExtensionCatalogRow(
                                extensionRecord: ext,
                                isBusy: busyExtensionIDs.contains(ext.id),
                                onToggleEnabled: {
                                    toggleExtension(ext)
                                },
                                onUninstall: {
                                    uninstallExtension(ext)
                                }
            )
        }
    }
}
            }

            if discoveredSafariExtensions.isEmpty == false {
                SettingsSectionCard(
                    title: "Safari Extensions Found On This Mac",
                    subtitle: "Discovered in `/Applications` and `~/Applications`"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(discoveredSafariExtensions, id: \.appexPath.path) { info in
                            SafariDiscoveryRow(
                                info: info,
                                isInstalled: installedExtensions.contains(where: {
                                    $0.appexBundleID == info.id || $0.sourceBundlePath == info.appPath.path || $0.sourceBundlePath == info.appexPath.path
                                }),
                                onInstall: {
                                    installDiscoveredSafariExtension(info)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private func discoverSafariExtensions() {
        discoveryTask?.cancel()
        statusMessage = nil
        isDiscoveringSafariExtensions = true

        discoveryTask = Task { @MainActor in
            let results = await browserManager.extensionManager.discoverSafariExtensions()
            guard !Task.isCancelled else { return }
            discoveredSafariExtensions = results
            isDiscoveringSafariExtensions = false
            discoveryTask = nil
            if results.isEmpty {
                statusMessage = "Sumi did not find any Safari Web Extensions in the scanned Applications folders."
            }
        }
    }

    private func installDiscoveredSafariExtension(_ info: SafariExtensionInfo) {
        SettingsViewStateDeferral.schedule {
            statusMessage = nil
            busyExtensionIDs.insert(info.id)
        }
        browserManager.extensionManager.installSafariExtension(info) { result in
            SettingsViewStateDeferral.schedule {
                guard busyExtensionIDs.contains(info.id) else { return }
                busyExtensionIDs.remove(info.id)
                switch result {
                case .success(let installed):
                    statusMessage = "Installed \(installed.name)."
                case .failure(let error):
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func toggleExtension(_ extensionRecord: InstalledExtension) {
        extensionOperationTasks[extensionRecord.id]?.cancel()
        busyExtensionIDs.insert(extensionRecord.id)
        extensionOperationTasks[extensionRecord.id] = Task { @MainActor in
            let nextStatusMessage: String
            do {
                if extensionRecord.isEnabled {
                    try await browserManager.extensionManager.disableExtension(
                        extensionRecord.id
                    )
                    nextStatusMessage = "Disabled \(extensionRecord.name)."
                } else {
                    let enabled = try await browserManager.extensionManager.enableExtension(
                        extensionRecord.id
                    )
                    nextStatusMessage = "Enabled \(enabled.name)."
                }
            } catch {
                nextStatusMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            statusMessage = nextStatusMessage
            busyExtensionIDs.remove(extensionRecord.id)
            extensionOperationTasks[extensionRecord.id] = nil
        }
    }

    private func uninstallExtension(_ extensionRecord: InstalledExtension) {
        extensionOperationTasks[extensionRecord.id]?.cancel()
        busyExtensionIDs.insert(extensionRecord.id)
        extensionOperationTasks[extensionRecord.id] = Task { @MainActor in
            let nextStatusMessage: String
            do {
                try await browserManager.extensionManager.uninstallExtension(
                    extensionRecord.id
                )
                nextStatusMessage = "Removed \(extensionRecord.name)."
            } catch {
                nextStatusMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            statusMessage = nextStatusMessage
            busyExtensionIDs.remove(extensionRecord.id)
            extensionOperationTasks[extensionRecord.id] = nil
        }
    }

    private func cancelExtensionPaneTasks() {
        discoveryTask?.cancel()
        discoveryTask = nil
        extensionOperationTasks.values.forEach { $0.cancel() }
        extensionOperationTasks.removeAll()
        isDiscoveringSafariExtensions = false
        busyExtensionIDs.removeAll()
    }
}

private struct ExtensionCatalogRow: View {
    let extensionRecord: InstalledExtension
    let isBusy: Bool
    let onToggleEnabled: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let iconPath = extensionRecord.iconPath,
                   let image = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(extensionRecord.name)
                    .font(.headline)

                Text("Version \(extensionRecord.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(extensionRecord.isEnabled ? "Enabled in Sumi’s Safari runtime" : "Installed but currently disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(extensionRecord.sourceBundlePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(extensionRecord.isEnabled ? "Disable" : "Enable") {
                    onToggleEnabled()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button("Remove", role: .destructive) {
                    onUninstall()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct SafariDiscoveryRow: View {
    let info: SafariExtensionInfo
    let isInstalled: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "safari")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.headline)

                Text(info.appPath.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(info.appexPath.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Reusable pane wrapper: fixed height + scrolling
private struct SettingsPane<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    private let fixedHeight: CGFloat = 500
    private let minWidth: CGFloat = 500

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .scrollIndicators(.automatic)
        .frame(minWidth: minWidth, maxWidth: 675)
        .frame(
            minHeight: fixedHeight,
            idealHeight: fixedHeight,
            maxHeight: fixedHeight
        )
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) var sumiSettings
    @State private var showingAddEngine = false

    var body: some View {
        @Bindable var settings = sumiSettings

        HStack(alignment: .top, spacing: 16) {
            // Hero card
            SettingsHeroCard()
                .frame(width: 320, height: 420)

            // Right side stacked cards
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionCard(
                        title: "Appearance",
                        subtitle: "Window appearance and visual style"
                    ) {
                        VStack{
                            HStack(alignment: .firstTextBaseline) {
                                Text("Pinned Tabs Look")
                                Spacer()
                                Picker(
                                    "pinned tabs",
                                    selection: $settings.pinnedTabsLook
                                ) {
                                    ForEach(PinnedTabsConfiguration.allCases) { config in
                                        Text(config.name).tag(config)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 220)
                            }
                        }

                    }
                    
                    SettingsSectionCard(
                        title: "Sumi Window",
                        subtitle: "Sumi keeps one fixed left-sidebar shell"
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle(
                                isOn: $settings
                                    .askBeforeQuit
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ask Before Quitting")
                                    Text(
                                        "Warn before quitting Sumi"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)

                            Label("Left sidebar shell is always on", systemImage: "sidebar.left")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Divider().opacity(0.4)
                            
                            Toggle(
                                isOn: $settings
                                    .showLinkStatusBar
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Link Status Bar")
                                    Text(
                                        "Show URL preview when hovering over links"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    SettingsSectionCard(
                        title: "Search",
                        subtitle: "Default provider for address bar"
                    ) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Search Engine")
                            Spacer()
                            Picker(
                                "Search Engine",
                                selection: $settings
                                    .searchEngineId
                            ) {
                                ForEach(SearchProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider.rawValue)
                                }
                                ForEach(sumiSettings.customSearchEngines) { engine in
                                    Text(engine.name).tag(engine.id.uuidString)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220)

                            Button {
                                showingAddEngine = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if let selected = sumiSettings.customSearchEngines.first(where: { $0.id.uuidString == sumiSettings.searchEngineId }) {
                            HStack {
                                Text(selected.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Remove") {
                                    sumiSettings.customSearchEngines.removeAll { $0.id == selected.id }
                                    sumiSettings.searchEngineId = SearchProvider.google.rawValue
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddEngine) {
                        CustomSearchEngineEditor { newEngine in
                            sumiSettings.customSearchEngines.append(newEngine)
                        }
                    }
                    
                    SettingsSectionCard(
                        title: "Performance",
                        subtitle: "Manage memory by unloading inactive tabs"
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Tab Unload Timeout")
                                Spacer()
                                Picker(
                                    "Tab Unload Timeout",
                                    selection: Binding<TimeInterval>(
                                        get: {
                                            nearestTimeoutOption(
                                                to: sumiSettings
                                                    .tabUnloadTimeout
                                            )
                                        },
                                        set: { newValue in
                                            sumiSettings
                                                .tabUnloadTimeout = newValue
                                        }
                                    )
                                ) {
                                    ForEach(unloadTimeoutOptions, id: \.self) {
                                        value in
                                        Text(formatTimeout(value)).tag(value)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 220)
                                .onAppear {
                                    sumiSettings
                                        .tabUnloadTimeout =
                                        nearestTimeoutOption(
                                            to: sumiSettings
                                                .tabUnloadTimeout
                                        )
                                }
                            }

                            Text(
                                "Automatically unload inactive tabs to reduce memory usage."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Button("Unload All Inactive Tabs") {
                                    browserManager.tabManager
                                        .unloadAllInactiveTabs()
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .frame(minHeight: 480)
    }
}

// MARK: - Placeholder Settings Views

struct ProfilesSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var profileToRename: Profile? = nil
    @State private var profileToDelete: Profile? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Profiles list and actions
            SettingsSectionCard(
                title: "Profiles",
                subtitle: "Create, switch, and manage browsing personas"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: showCreateDialog) {
                            Label("Create Profile", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Create Profile")
                        .accessibilityHint(
                            "Open dialog to create a new profile"
                        )

                        Spacer()
                    }

                    Divider().opacity(0.4)

                    if browserManager.profileManager.profiles.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(.secondary)
                            Text("No profiles yet. Create one to get started.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(
                                browserManager.profileManager.profiles,
                                id: \.id
                            ) { profile in
                                ProfileRowView(
                                    profile: profile,
                                    isCurrent: browserManager.currentProfile?.id
                                        == profile.id,
                                    spacesCount: spacesCount(for: profile),
                                    tabsCount: tabsCount(for: profile),
                                    dataSizeDescription: "Shared store",
                                    pinnedCount: pinnedCount(for: profile),
                                    onMakeCurrent: {
                                        Task {
                                            await browserManager.switchToProfile(
                                                profile
                                            )
                                        }
                                    },
                                    onRename: { startRename(profile) },
                                    onDelete: { startDelete(profile) },
                                    onManageData: {
                                        showDataManagement(for: profile)
                                    }
                                )
                                .accessibilityLabel("Profile \(profile.name)")
                                .accessibilityHint(
                                    browserManager.currentProfile?.id
                                        == profile.id
                                        ? "Current profile" : "Inactive profile"
                                )
                            }
                        }
                    }
                }

                Divider().opacity(0.4)

              }

            // Space assignments management
            SettingsSectionCard(
                title: "Space Assignments",
                subtitle: "Assign spaces to specific profiles"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Bulk actions
                    HStack(spacing: 8) {
                        Button(action: assignAllSpacesToCurrentProfile) {
                            Label(
                                "Assign All to Current Profile",
                                systemImage: "checkmark.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(
                            "Assign all spaces to current profile"
                        )

                        Button(action: resetAllSpaceAssignments) {
                            Label(
                                "Reset to Default Profile",
                                systemImage: "arrow.uturn.backward"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Reset space assignments to none")

        
                        Spacer()
                    }

                    Divider().opacity(0.4)

                    if browserManager.tabManager.spaces.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group")
                                .foregroundStyle(.secondary)
                            Text(
                                "No spaces yet. Create a space to assign profiles."
                            )
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(browserManager.tabManager.spaces, id: \.id)
                            { space in
                                SpaceAssignmentRowView(space: space)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers
    private func spacesCount(for profile: Profile) -> Int {
        browserManager.tabManager.spaces.filter { $0.profileId == profile.id }
            .count
    }

    private func tabsCount(for profile: Profile) -> Int {
        let spaceIds = Set(
            browserManager.tabManager.spaces.filter {
                $0.profileId == profile.id
            }.map { $0.id }
        )
        return browserManager.tabManager.allTabs().filter { tab in
            if let sid = tab.spaceId { return spaceIds.contains(sid) }
            return false
        }.count
    }

    private func pinnedCount(for profile: Profile) -> Int {
        // Count space‑pinned tabs in spaces assigned to this profile
        let spaceIds = browserManager.tabManager.spaces
            .filter { $0.profileId == profile.id }
            .map { $0.id }
        var total = 0
        for sid in spaceIds {
            total += browserManager.tabManager.launcherProjection(for: sid).launcherCount
        }
        return total
    }

    // MARK: - Actions
    private func showCreateDialog() {
        browserManager.showDialog(
            ProfileCreationDialog(
                isNameAvailable: { proposed in
                    let trimmed = proposed.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !trimmed.isEmpty else { return false }
                    return !browserManager.profileManager.profiles.contains {
                        $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }
                },
                onCreate: { name, icon in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let safeIcon = SumiPersistentGlyph.normalizedProfileIconValue(
                        icon.isEmpty ? SumiPersistentGlyph.profileSystemImageFallback : icon
                    )
                    let created = browserManager.profileManager.createProfile(
                        name: trimmed,
                        icon: safeIcon
                    )
                    Task { await browserManager.switchToProfile(created) }
                    browserManager.closeDialog()
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            )
        )
    }

    private func startRename(_ profile: Profile) {
        profileToRename = profile
        browserManager.showDialog(
            ProfileRenameDialog(
                originalProfile: profile,
                isNameAvailable: { proposed in
                    let trimmed = proposed.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    return !browserManager.profileManager.profiles.contains {
                        $0.id != profile.id
                            && $0.name.caseInsensitiveCompare(trimmed)
                                == .orderedSame
                    }
                },
                onSave: { newName, newIcon in
                    guard let target = profileToRename else {
                        browserManager.closeDialog()
                        return
                    }
                    target.name = newName
                    target.icon = SumiPersistentGlyph.normalizedProfileIconValue(newIcon)
                    browserManager.profileManager.persistProfiles()
                    browserManager.closeDialog()
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            )
        )
    }

    private func startDelete(_ profile: Profile) {
        let isLast = browserManager.profileManager.profiles.count <= 1
        let stats = (
            spaces: spacesCount(for: profile),
            tabs: tabsCount(for: profile)
        )
        let dialog = ProfileDeleteConfirmationDialog(
            profileName: profile.name,
            profileIcon: profile.icon,
            spacesCount: stats.spaces,
            tabsCount: stats.tabs,
            isLastProfile: isLast,
            onDelete: {
                guard browserManager.profileManager.profiles.count > 1 else {
                    browserManager.closeDialog()
                    return
                }
                browserManager.deleteProfile(profile)
            },
            onCancel: { browserManager.closeDialog() }
        )
        browserManager.showDialog(dialog)
    }

    private func showDataManagement(for profile: Profile) {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "internaldrive",
                        title: "Manage Data",
                        subtitle: "Profile data management"
                    )
                },
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Each profile maintains its own isolated website data store.")
                        Text("Privacy tools are available under the Privacy tab.")
                            .foregroundStyle(.secondary)
                    }
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "Close", variant: .primary) {
                            browserManager.closeDialog()
                        }
                    ])
                }
            )
        }
    }

    // MARK: - Space assignment helpers and views
    private func assign(space: Space, to id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func assignAllSpacesToCurrentProfile() {
        guard let pid = browserManager.currentProfile?.id else { return }
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(spaceId: sp.id, toProfile: pid)
        }
    }

    private func resetAllSpaceAssignments() {
        guard
            let defaultProfileId = browserManager.profileManager.profiles.first?
                .id
        else { return }
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(
                spaceId: sp.id,
                toProfile: defaultProfileId
            )
        }
    }

    
    private func resolvedProfile(for id: UUID?) -> Profile? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: {
            $0.id == id
        })
    }

    private struct SpaceAssignmentRowView: View {
        @EnvironmentObject var browserManager: BrowserManager
        let space: Space

        var body: some View {
            HStack(spacing: 12) {
                // Space icon
                Group {
                    if SumiPersistentGlyph.presentsAsEmoji(space.icon) {
                        Text(space.icon)
                            .font(.system(size: 14))
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(space.icon))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                }
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        SpaceProfileBadge(space: space, size: .compact)
                            .environmentObject(browserManager)
                        Text(currentProfileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Quick action to set to current profile
                if let current = browserManager.currentProfile {
                    Button {
                        assign(space: space, to: current.id)
                    } label: {
                        Label(
                            "Assign to \(current.name)",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Profile picker menu
                Menu {
                    // Use compact picker inside menu
                    let binding = Binding<UUID>(
                        get: {
                            space.profileId ?? browserManager.profileManager
                                .profiles.first?.id ?? UUID()
                        },
                        set: { newId in assign(space: space, to: newId) }
                    )
                    Text("Current: \(currentProfileName)")
                        .foregroundStyle(.secondary)
                    Divider()
                    ProfilePickerView(
                        selectedProfileId: binding,
                        onSelect: { _ in },
                        compact: true
                    )
                    .environmentObject(browserManager)
                } label: {
                    Label("Change", systemImage: "person.crop.circle")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var currentProfileName: String {
            if let pid = space.profileId,
                let p = browserManager.profileManager.profiles.first(where: {
                    $0.id == pid
                })
            {
                return p.name
            }
            // If no profile assigned, show the default profile name
            return browserManager.profileManager.profiles.first?.name
                ?? "Default"
        }

        private func assign(space: Space, to id: UUID) {
            browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
        }
    }
}

struct ShortcutsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) var sumiSettings
    @State private var searchText = ""
    @State private var selectedCategory: ShortcutCategory? = nil
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager

    private var filteredShortcuts: [KeyboardShortcut] {
        var filtered = keyboardShortcutManager.shortcuts

        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.action.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { shortcut in
                shortcut.action.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by category and display name
        return filtered.sorted {
            if $0.action.category != $1.action.category {
                return $0.action.category.rawValue < $1.action.category.rawValue
            }
            return $0.action.displayName < $1.action.displayName
        }
    }

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: filteredShortcuts, by: { $0.action.category })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with search and reset
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Customize keyboard shortcuts for faster navigation")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset to Defaults") {
                    keyboardShortcutManager.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider().opacity(0.4)

            // Search and filter controls
            HStack(spacing: 12) {
                TextField("Search shortcuts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryFilterChip(
                            title: "All",
                            icon: nil,
                            isSelected: selectedCategory == nil,
                            onTap: { selectedCategory = nil }
                        )
                        ForEach(ShortcutCategory.allCases, id: \.self) { category in
                            CategoryFilterChip(
                                title: category.displayName,
                                icon: category.icon,
                                isSelected: selectedCategory == category,
                                onTap: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            Divider().opacity(0.4)

            // Shortcuts list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(ShortcutCategory.allCases, id: \.self) { category in
                        if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                            CategorySection(
                                category: category,
                                shortcuts: categoryShortcuts
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
    }
}

/// MARK: - Category Section
private struct CategorySection: View {
    let category: ShortcutCategory
    let shortcuts: [KeyboardShortcut]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(category.displayName, systemImage: category.icon)
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.id) { shortcut in
                    ShortcutRowView(shortcut: shortcut)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// MARK: - Shortcut Row
private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager
    @State private var localKeyCombination: KeyCombination

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        self._localKeyCombination = State(initialValue: shortcut.keyCombination)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Action description
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.action.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(shortcut.action.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Shortcut recorder
            if shortcut.isCustomizable {
                ShortcutRecorderView(
                    keyCombination: $localKeyCombination,
                    action: shortcut.action,
                    shortcutManager: keyboardShortcutManager,
                    onRecordingComplete: {
                        updateShortcut()
                    }
                )
            } else {
                Text(shortcut.keyCombination.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Enable toggle
            if shortcut.isCustomizable {
                Toggle("", isOn: Binding(
                    get: { shortcut.isEnabled },
                    set: { newValue in
                        keyboardShortcutManager.toggleShortcut(action: shortcut.action, isEnabled: newValue)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: shortcut) { _, newShortcut in
            localKeyCombination = newShortcut.keyCombination
        }
    }

    private func updateShortcut() {
        keyboardShortcutManager.updateShortcut(action: shortcut.action, keyCombination: localKeyCombination)
    }
}

// MARK: - Category Filter Chip
private struct CategoryFilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) var sumiSettings

    var body: some View {
        @Bindable var settings = sumiSettings
        return VStack(alignment: .leading, spacing: 16) {
            #if DEBUG
            SettingsSectionCard(
                title: "Debug Options",
                subtitle: "Development and debugging features"
            ) {
                Toggle(
                    isOn: $settings.debugToggleUpdateNotification
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Update Notification")
                        Text(
                            "Force display the sidebar update notification for appearance debugging"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            #endif
        }
        .padding()
    }
}

// MARK: - Helper Functions
private let unloadTimeoutOptions: [TimeInterval] = [
    300,  // 5 min
    600,  // 10 min
    900,  // 15 min
    1800,  // 30 min
    2700,  // 45 min
    3600,  // 1 hr
    7200,  // 2 hr
    14400,  // 4 hr
    28800,  // 8 hr
    43200,  // 12 hr
    86400,  // 24 hr
]

private func nearestTimeoutOption(to value: TimeInterval) -> TimeInterval {
    guard
        let nearest = unloadTimeoutOptions.min(by: {
            abs($0 - value) < abs($1 - value)
        })
    else {
        return value
    }
    return nearest
}

// MARK: - Styled Components
struct SettingsSectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        )
    }
}

struct SettingsHeroCard: View {
    @EnvironmentObject var browserManager: BrowserManager

    private var heroGradient: SpaceGradient {
        browserManager.tabManager.currentSpace?.workspaceTheme.gradient ?? .default
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                BarycentricGradientView(
                    gradient: heroGradient
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(12)
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sumi")
                    .font(.system(size: 24, weight: .bold))
                Text("BROWSER")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                Image(systemName: "doc.on.doc")
                Image(systemName: "gearshape")
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .shadow(color: Color.black.opacity(0.1), radius: 14, y: 6)
        )
    }
}

struct SettingsPlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack { Spacer() }
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title).font(.title2).fontWeight(.semibold)
                Text(subtitle).foregroundStyle(.secondary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Site Search Settings

struct SiteSearchSettingsCard: View {
    @Environment(\.sumiSettings) var sumiSettings
    @State private var showingAddSheet = false
    @State private var editingEntry: SiteSearchEntry? = nil

    var body: some View {
        @Bindable var settings = sumiSettings
        SettingsSectionCard(
            title: "Site Search",
            subtitle: "Tab-to-Search shortcuts for quick site searches"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sumiSettings.siteSearchEntries) { entry in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(entry.color)
                            .frame(width: 14, height: 14)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(entry.domain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            editingEntry = entry
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            sumiSettings.siteSearchEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 8) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Site", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("Reset to Defaults") {
                        sumiSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                sumiSettings.siteSearchEntries.append(newEntry)
            }
        }
        .sheet(item: $editingEntry) { entry in
            SiteSearchEntryEditor(entry: entry) { updated in
                if let idx = sumiSettings.siteSearchEntries.firstIndex(where: { $0.id == updated.id }) {
                    sumiSettings.siteSearchEntries[idx] = updated
                }
            }
        }
    }
}

struct SiteSearchEntryEditor: View {
    let entry: SiteSearchEntry?
    let onSave: (SiteSearchEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var domain: String = ""
    @State private var searchURLTemplate: String = ""
    @State private var colorHex: String = "#666666"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry == nil ? "Add Site Search" : "Edit Site Search")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Domain (e.g. youtube.com)", text: $domain)
                TextField("Search URL (use {query})", text: $searchURLTemplate)
                TextField("Color Hex (e.g. #E62617)", text: $colorHex)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let saved = SiteSearchEntry(
                        id: entry?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchURLTemplate: searchURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || domain.isEmpty || searchURLTemplate.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onAppear {
            if let entry {
                name = entry.name
                domain = entry.domain
                searchURLTemplate = entry.searchURLTemplate
                colorHex = entry.colorHex
            }
        }
    }
}

private func formatTimeout(_ seconds: TimeInterval) -> String {
    if seconds < 3600 {  // under 1 hour
        let minutes = Int(seconds / 60)
        return minutes == 1 ? "1 min" : "\(minutes) mins"
    } else if seconds < 86400 {  // under 24 hours
        let hours = seconds / 3600.0
        let rounded = hours.rounded()
        let isWhole = abs(hours - rounded) < 0.01
        if isWhole {
            let wholeHours = Int(rounded)
            return wholeHours == 1 ? "1 hr" : "\(wholeHours) hrs"
        } else {
            // Show one decimal for non-integer hours
            return String(format: "%.1f hrs", hours)
        }
    } else {
        // 24 hours (cap in UI)
        return "24 hr"
    }
}
