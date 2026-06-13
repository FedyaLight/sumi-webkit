//
//  SettingsView.swift
//  Sumi
//
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsViewStateDeferral {
    static func schedule(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            mutation()
        }
    }
}

/// Profile management (also used in the in-tab settings surface).
struct SumiProfilesSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfilesSettingsView()
        }
    }
}

struct SumiDataRecoverySettingsPane: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @State private var importPreview: SumiImportPreview?
    @State private var selectedCategories: Set<SumiImportCategory> = []
    @State private var applyMode: SumiImportApplyMode = .merge
    @State private var statusMessage: String?
    @State private var isWorking = false

    private let importService = SumiBrowserImportService()
    private let backupService = SumiBackupService()
    private let transferService = SumiTransferExportService()
    private let applier = SumiImportApplier()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Browser Import",
                subtitle: "Bring spaces, launchers, tabs, folders, themes, profiles, and bookmarks into Sumi."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsActionRow(
                        title: "Arc",
                        subtitle: "Import Arc spaces, profiles, essentials, pinned items, open tabs, folders, themes, and bookmarks.",
                        systemImage: "square.stack.3d.up",
                        buttonTitle: "Import"
                    ) {
                        loadPreview { try importService.previewArcImport() }
                    }
                    .disabled(isWorking)

                    SettingsActionRow(
                        title: "Zen",
                        subtitle: "Import Zen workspaces, essentials, pinned items, open tabs, folders, themes, containers, and bookmarks.",
                        systemImage: "tray.and.arrow.down",
                        buttonTitle: "Import"
                    ) {
                        importZen()
                    }
                    .disabled(isWorking)

                    SettingsActionRow(
                        title: "Chrome, Safari, Firefox",
                        subtitle: "Import bookmarks from browsers that do not expose Arc/Zen-style spaces or launchers.",
                        systemImage: "book",
                        buttonTitle: "Import"
                    ) {
                        browserManager.importBookmarksFromMenu()
                    }
                    .disabled(isWorking)

                    SettingsActionRow(
                        title: "Import from File",
                        subtitle: "Open a .sumibackup, .sumiexport, or browser2zen-compatible JSON file.",
                        systemImage: "doc.badge.arrow.up",
                        buttonTitle: "Open"
                    ) {
                        importFromFile()
                    }
                    .disabled(isWorking)
                }
            }

            SettingsSection(
                title: "Export & Backup",
                subtitle: "Write portable Sumi data without cookies, passwords, caches, downloads, or WebKit website data."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsActionRow(
                        title: "Export for Zen",
                        subtitle: "Create browser2zen-compatible JSON with a Sumi extension block for future Sumi-to-Zen support.",
                        systemImage: "arrow.up.doc",
                        buttonTitle: "Export"
                    ) {
                        exportBrowser2Zen()
                    }
                    .disabled(isWorking)

                    SettingsActionRow(
                        title: "Backup Sumi",
                        subtitle: "Create a .sumibackup with logical Sumi data.",
                        systemImage: "archivebox",
                        buttonTitle: "Backup"
                    ) {
                        backupSumi()
                    }
                    .disabled(isWorking)

                    SettingsActionRow(
                        title: "Sumi data folder",
                        subtitle: "Open the app-support directory that contains runtime stores and automatic pre-restore backups.",
                        systemImage: "folder",
                        buttonTitle: "Reveal"
                    ) {
                        revealDataFolder()
                    }
                }
            }

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: previewPresented) {
            if let importPreview {
                SumiImportPreviewSheet(
                    preview: importPreview,
                    selectedCategories: $selectedCategories,
                    applyMode: $applyMode,
                    isWorking: isWorking,
                    onCancel: {
                        self.importPreview = nil
                    },
                    onApply: {
                        applyCurrentPreview()
                    }
                )
            }
        }
    }

    private var previewPresented: Binding<Bool> {
        Binding(
            get: { importPreview != nil },
            set: { presented in
                if !presented {
                    importPreview = nil
                }
            }
        )
    }

    private func loadPreview(_ operation: () throws -> SumiImportPreview) {
        do {
            let preview = try operation()
            importPreview = preview
            selectedCategories = preview.suggestedCategories
            applyMode = preview.defaultMode
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importZen() {
        let profiles = importService.detectedZenProfiles()
        if profiles.count == 1, let profile = profiles.first {
            loadPreview { try importService.previewZenImport(profileURL: profile) }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Zen"
        if let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            panel.directoryURL = root.appendingPathComponent("zen/Profiles", isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPreview { try importService.previewZenImport(profileURL: url) }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.sumiBackup, .sumiTransfer, .json]
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPreview {
            try withSecurityScoped(url) {
                try importService.previewFileImport(fileURL: url)
            }
        }
    }

    private func exportBrowser2Zen() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sumiTransfer, .json]
        panel.nameFieldStringValue = "sumi-browser2zen.sumiexport"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let payload = try transferService.exportBrowser2ZenDocument(from: browserManager)
            try withSecurityScoped(url) {
                try payload.write(to: url, options: .atomic)
            }
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func backupSumi() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sumiBackup]
        panel.nameFieldStringValue = "Sumi-\(Self.backupDateStamp()).sumibackup"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try withSecurityScoped(url) {
                try backupService.writeBackup(from: browserManager, to: url)
            }
            statusMessage = "Backed up \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyCurrentPreview() {
        guard let importPreview else { return }
        isWorking = true
        statusMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let result = try await applier.apply(
                    importPreview.data,
                    to: browserManager,
                    categories: selectedCategories,
                    mode: applyMode
                )
                var messages = result.warnings
                if let preRestoreBackupURL = result.preRestoreBackupURL {
                    messages.append("Pre-restore backup: \(preRestoreBackupURL.lastPathComponent)")
                }
                statusMessage = messages.isEmpty ? "Import complete." : messages.joined(separator: " ")
                self.importPreview = nil
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func revealDataFolder() {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let bundleId = SumiAppIdentity.runtimeBundleIdentifier
        let target = support.appendingPathComponent(bundleId, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func withSecurityScoped<T>(_ url: URL, operation: () throws -> T) rethrows -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    private static func backupDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

private struct SumiImportPreviewSheet: View {
    let preview: SumiImportPreview
    @Binding var selectedCategories: Set<SumiImportCategory>
    @Binding var applyMode: SumiImportApplyMode
    var isWorking: Bool
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.title3.weight(.semibold))
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("Mode", selection: $applyMode) {
                ForEach(SumiImportApplyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(SumiImportCategory.allCases) { category in
                    Toggle(isOn: categoryBinding(category)) {
                        Text(category.title)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!preview.suggestedCategories.contains(category))
                }
            }

            if preview.warnings.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(applyMode == .replace ? "Restore" : "Import", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCategories.isEmpty || isWorking)
            }
        }
        .padding(24)
        .frame(minWidth: 520, maxWidth: 680)
    }

    private var summaryText: String {
        let summary = preview.summary
        return "\(summary.profiles) profiles, \(summary.spaces) spaces, \(summary.essentials) essentials, \(summary.pinnedLaunchers) pinned, \(summary.regularTabs) regular tabs, \(summary.folders) folders, \(summary.bookmarks) bookmarks"
    }

    private func categoryBinding(_ category: SumiImportCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { enabled in
                if enabled {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }
}

struct SumiExtensionsSettingsPane: View {
    @Environment(\.sumiSettings) private var sumiSettingsModel
    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @State private var busyExtensionIDs: Set<String> = []
    @State private var statusMessage: String?
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
                            cancelExtensionPaneTasks()
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
            cancelExtensionPaneTasks()
        }
        .onChange(of: sumiSettings.extensionsSettingsSubPane) { _, subPane in
            if subPane != .extensions {
                cancelExtensionPaneTasks()
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
            extensionsBody(
                installedExtensions: extensionSurfaceStore.installedExtensions
            )
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
        installedExtensions: [InstalledExtension]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                                siteAccessPolicy: browserManager.extensionsModule
                                    .siteAccessPolicy(
                                        extensionId: ext.id,
                                        profileId: browserManager.currentProfile?.id
                                    ),
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
                    onStatus: { statusMessage = $0 }
                )
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
                    try await browserManager.extensionsModule.disableExtension(
                        extensionRecord.id
                    )
                    nextStatusMessage = "Disabled \(extensionRecord.name)."
                } else {
                    let enabled = try await browserManager.extensionsModule.enableExtension(
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
                try await browserManager.extensionsModule.uninstallExtension(
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
        extensionOperationTasks.values.forEach { $0.cancel() }
        extensionOperationTasks.removeAll()
        busyExtensionIDs.removeAll()
    }
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

    private var rowSummary: String {
        var parts = ["Version \(extensionRecord.version)"]
        if showsWebsiteAccessControls {
            parts.append("Website access: \(defaultSiteAccess.title)")
        }
        if privateAccessAllowed {
            parts.append("Private Browsing")
        }
        return parts.joined(separator: " - ")
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
               raw.isEmpty == false
            {
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

// MARK: - Profiles Settings

struct ProfilesSettingsView: View {
    private enum ProfileEditorPresentation: Identifiable {
        case add
        case edit(UUID)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let id):
                return "edit-\(id.uuidString)"
            }
        }
    }

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var profileEditorPresentation: ProfileEditorPresentation?

    var body: some View {
        SettingsSection(
            title: "Browsing Profiles",
            subtitle: "Each profile keeps website data, history, and extension state separate."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if browserManager.profileManager.profiles.isEmpty {
                    SettingsEmptyState(
                        systemImage: "person.2",
                        title: "No Profiles",
                        detail: "Add a profile to keep browsing data separate."
                    )

                    SettingsDivider()

                    profileToolbar
                } else {
                    profileRows

                    SettingsDivider()

                    profileToolbar
                }
            }
        }
        .sheet(item: $profileEditorPresentation) { presentation in
            profileEditorSheet(for: presentation)
                .environment(\.resolvedThemeContext, profileEditorThemeContext)
                .environment(\.colorScheme, profileEditorColorScheme)
                .preferredColorScheme(profileEditorColorScheme)
        }
    }

    // MARK: - Helpers
    private var profileEditorThemeContext: ResolvedThemeContext {
        themeContext.nativeSurfaceThemeContext
    }

    private var profileEditorColorScheme: ColorScheme {
        profileEditorThemeContext.nativeSurfaceColorScheme
    }

    private var profileRows: some View {
        VStack(spacing: 0) {
            ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                ProfileRowView(
                    profile: profile,
                    spacesCount: spacesCount(for: profile),
                    tabsCount: tabsCount(for: profile),
                    canDelete: canDelete(profile),
                    onEdit: { startEdit(profile) },
                    onDelete: { startDelete(profile) }
                )

                if profile.id != browserManager.profileManager.profiles.last?.id {
                    SettingsDivider()
                        .padding(.leading, 58)
                }
            }
        }
    }

    private var profileToolbar: some View {
        HStack {
            Spacer()
            Button("Add Profile...") {
                profileEditorPresentation = .add
            }
            .buttonStyle(.bordered)
        }
    }

    private func canDelete(_ profile: Profile) -> Bool {
        browserManager.profileManager.profiles.count > 1
            && browserManager.profileManager.profiles.contains { $0.id == profile.id }
    }

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

    // MARK: - Actions
    @ViewBuilder
    private func profileEditorSheet(
        for presentation: ProfileEditorPresentation
    ) -> some View {
        switch presentation {
        case .add:
            ProfileEditorSheet(
                mode: .create,
                isNameAvailable: { isProfileNameAvailable($0) },
                onSave: { name, icon in
                    createProfile(name: name, icon: icon)
                },
                onCancel: {
                    profileEditorPresentation = nil
                }
            )
        case .edit(let profileID):
            if let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileID }) {
                ProfileEditorSheet(
                    mode: .edit,
                    initialName: profile.name,
                    initialIcon: profile.icon,
                    isNameAvailable: {
                        isProfileNameAvailable($0, excluding: profile.id)
                    },
                    onSave: { name, icon in
                        updateProfile(profile, name: name, icon: icon)
                    },
                    onCancel: {
                        profileEditorPresentation = nil
                    }
                )
            } else {
                EmptyView()
            }
        }
    }

    private func startEdit(_ profile: Profile) {
        profileEditorPresentation = .edit(profile.id)
    }

    private func startDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(profile.name)”?"
        alert.informativeText = deleteConfirmationMessage(for: profile)
        if let icon = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete Profile"
        ) {
            alert.icon = icon
        }

        let deleteButton = alert.addButton(withTitle: "Delete Profile")
        deleteButton.hasDestructiveAction = true

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        
        if alert.runModal() == .alertFirstButtonReturn {
            confirmDelete(profile)
        }
    }

    private func createProfile(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isProfileNameAvailable(trimmed) else { return }

        _ = browserManager.profileManager.createProfile(
            name: trimmed,
            icon: SumiProfileIcon.storedValue(icon)
        )
        profileEditorPresentation = nil
    }

    private func updateProfile(_ profile: Profile, name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              isProfileNameAvailable(trimmed, excluding: profile.id)
        else { return }

        profile.name = trimmed
        profile.icon = SumiProfileIcon.storedValue(icon)
        browserManager.profileManager.persistProfiles()
        profileEditorPresentation = nil
    }

    private func confirmDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }
        browserManager.deleteProfile(profile)
    }

    private func isProfileNameAvailable(
        _ proposedName: String,
        excluding excludedProfileID: UUID? = nil
    ) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !browserManager.profileManager.profiles.contains {
            $0.id != excludedProfileID
                && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func deleteConfirmationMessage(for profile: Profile) -> String {
        let spaces = spacesCount(for: profile)
        let tabs = tabsCount(for: profile)
        let spaceText = spaces == 1 ? "1 space" : "\(spaces) spaces"
        let tabText = tabs == 1 ? "1 tab" : "\(tabs) tabs"
        return "\(spaceText) and \(tabText) that use this profile will move to another profile. Website data stored for this profile will be deleted."
    }
}
