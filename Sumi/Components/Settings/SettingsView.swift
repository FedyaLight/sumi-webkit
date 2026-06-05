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
    @State private var chromeMV3ManagerListViewModel:
        ChromeMV3ExtensionManagerListViewModel?
    @State private var chromeMV3ManagerDetailViewModel:
        ChromeMV3ExtensionManagerDetailViewModel?

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
                    chromeMV3ManagerBody
                        .onAppear {
                            refreshChromeMV3Manager()
                        }
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

    private var chromeMV3ManagerRootURL: URL {
        ChromeMV3ExtensionManagerStoreLocation.defaultRootURL()
    }

    private var chromeMV3ManagerBody: some View {
        let list = chromeMV3ManagerListViewModel
            ?? browserManager.extensionsModule
                .chromeMV3ExtensionManagerListViewModelIfEnabled(
                    rootURL: chromeMV3ManagerRootURL
                )
            ?? ChromeMV3ExtensionManagerViewModelBuilder.makeListViewModel(
                rootURL: chromeMV3ManagerRootURL,
                gate: browserManager.extensionsModule.chromeMV3ExtensionManagerGate()
            )

        return VStack(alignment: .leading, spacing: 12) {
            ChromeMV3ExtensionManagerView(
                listViewModel: list,
                selectedDetail: chromeMV3ManagerDetailViewModel,
                onLoadUnpacked: { loadChromeMV3UnpackedFolder() },
                onImportArchive: { importChromeMV3LocalArchive() },
                onSelectExtension: { profileID, extensionID in
                    selectChromeMV3Extension(
                        profileID: profileID,
                        extensionID: extensionID
                    )
                },
                onRunAction: { action, profileID, extensionID in
                    runChromeMV3ManagerAction(
                        action,
                        profileID: profileID,
                        extensionID: extensionID
                    )
                },
                onRunPermissionControl: {
                    kind,
                    profileID,
                    extensionID,
                    value in
                    runChromeMV3PermissionControl(
                        kind,
                        profileID: profileID,
                        extensionID: extensionID,
                        value: value
                    )
                },
                onCopyDiagnosticsJSON: { profileID, extensionID in
                    copyChromeMV3DiagnosticsJSON(
                        profileID: profileID,
                        extensionID: extensionID
                    )
                }
            )

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshChromeMV3Manager() {
        chromeMV3ManagerListViewModel = browserManager.extensionsModule
            .chromeMV3ExtensionManagerListViewModelIfEnabled(
                rootURL: chromeMV3ManagerRootURL
            )
        if let selected = chromeMV3ManagerDetailViewModel {
            chromeMV3ManagerDetailViewModel = browserManager.extensionsModule
                .chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                    rootURL: chromeMV3ManagerRootURL,
                    profileID: selected.listItem.profileID,
                    extensionID: selected.listItem.extensionID
                )
        } else if let first = chromeMV3ManagerListViewModel?.items.first {
            selectChromeMV3Extension(
                profileID: first.profileID,
                extensionID: first.extensionID
            )
        }
    }

    private func selectChromeMV3Extension(
        profileID: String,
        extensionID: String
    ) {
        chromeMV3ManagerDetailViewModel = browserManager.extensionsModule
            .chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: chromeMV3ManagerRootURL,
                profileID: profileID,
                extensionID: extensionID
            )
    }

    private func loadChromeMV3UnpackedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import Unpacked"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let rootURL = try ChromeMV3ExtensionManagerStoreLocation
                .ensureDefaultRootURL()
            let result = browserManager.extensionsModule
                .chromeMV3InstallUnpackedThroughManager(
                    rootURL: rootURL,
                    sourceURL: sourceURL
                )
            applyChromeMV3ManagerResult(result)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importChromeMV3LocalArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.zip,
            UTType(filenameExtension: "crx"),
        ].compactMap { $0 }
        panel.prompt = "Import ZIP"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let result = browserManager.extensionsModule
            .chromeMV3ImportLocalArchiveThroughManager(
                rootURL: chromeMV3ManagerRootURL,
                sourceURL: sourceURL
            )
        applyChromeMV3ManagerResult(result)
    }

    private func runChromeMV3ManagerAction(
        _ action: ChromeMV3ExtensionManagerActionKind,
        profileID: String,
        extensionID: String
    ) {
        guard profileID.isEmpty == false, extensionID.isEmpty == false else {
            if action == .chromeWebStoreInstall {
                applyChromeMV3ManagerResult(
                    browserManager.extensionsModule
                        .chromeMV3ChromeWebStoreInstallDiagnosticThroughManager(
                            rootURL: chromeMV3ManagerRootURL
                        )
                )
            }
            return
        }

        let rootURL = chromeMV3ManagerRootURL
        let result: ChromeMV3ExtensionManagerActionResult
        switch action {
        case .enableInternal:
            result = browserManager.extensionsModule
                .chromeMV3SetInternalExtensionEnabledThroughManager(
                    true,
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .disableInternal:
            result = browserManager.extensionsModule
                .chromeMV3SetInternalExtensionEnabledThroughManager(
                    false,
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .rebuild:
            result = browserManager.extensionsModule
                .chromeMV3RebuildThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .retryDiagnostics:
            result = browserManager.extensionsModule
                .chromeMV3RetryDiagnosticsThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .runDiagnostics:
            result = browserManager.extensionsModule
                .chromeMV3RunDiagnosticsThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .runReviewedResourceDiagnosticAction:
            Task { @MainActor in
                let result = await browserManager.extensionsModule
                    .chromeMV3RunReviewedResourceDiagnosticActionThroughManager(
                        rootURL: rootURL,
                        profileID: profileID,
                        extensionID: extensionID
                    )
                applyChromeMV3ManagerResult(result)
            }
            return
        case .recover:
            result = browserManager.extensionsModule
                .chromeMV3RecoverThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .uninstall:
            result = browserManager.extensionsModule
                .chromeMV3UninstallThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .reset:
            result = browserManager.extensionsModule
                .chromeMV3ResetThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .chromeWebStoreInstall:
            result = browserManager.extensionsModule
                .chromeMV3ChromeWebStoreInstallDiagnosticThroughManager(
                    rootURL: chromeMV3ManagerRootURL
                )
        case .openActionPopup:
            result = browserManager.extensionsModule
                .chromeMV3OpenActionPopupThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .openOptions:
            result = browserManager.extensionsModule
                .chromeMV3OpenOptionsThroughManager(
                    rootURL: rootURL,
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .closePopupOptions:
            result = browserManager.extensionsModule
                .chromeMV3ClosePopupOptionsThroughManager(
                    profileID: profileID,
                    extensionID: extensionID
                )
        case .updateFromUnpacked:
            updateChromeMV3FromUnpackedFolder(
                profileID: profileID,
                extensionID: extensionID
            )
            return
        case .exportDiagnosticsJSON:
            copyChromeMV3DiagnosticsJSON(
                profileID: profileID,
                extensionID: extensionID
            )
            return
        case .installUnpacked, .importZipArchive, .importCRXArchive:
            return
        }
        applyChromeMV3ManagerResult(result)
    }

    private func runChromeMV3PermissionControl(
        _ kind: ChromeMV3ExtensionManagerPermissionControlKind,
        profileID: String,
        extensionID: String,
        value: String
    ) {
        guard profileID.isEmpty == false, extensionID.isEmpty == false else {
            return
        }
        let result = browserManager.extensionsModule
            .chromeMV3RunPermissionControlThroughManager(
                kind,
                rootURL: chromeMV3ManagerRootURL,
                profileID: profileID,
                extensionID: extensionID,
                value: value
            )
        statusMessage = result.diagnostics.first
            ?? (result.succeeded ? "Permission control succeeded." : "Permission control blocked.")
        refreshChromeMV3Manager()
    }

    private func updateChromeMV3FromUnpackedFolder(
        profileID: String,
        extensionID: String
    ) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Update"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let result = browserManager.extensionsModule
            .chromeMV3UpdateUnpackedThroughManager(
                rootURL: chromeMV3ManagerRootURL,
                profileID: profileID,
                extensionID: extensionID,
                sourceURL: sourceURL
            )
        applyChromeMV3ManagerResult(result)
    }

    private func copyChromeMV3DiagnosticsJSON(
        profileID: String,
        extensionID: String
    ) {
        let result = browserManager.extensionsModule
            .chromeMV3ExportDiagnosticsJSONThroughManager(
                rootURL: chromeMV3ManagerRootURL,
                profileID: profileID,
                extensionID: extensionID
            )
        if let json = result.diagnosticsJSON {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
        applyChromeMV3ManagerResult(result)
    }

    private func applyChromeMV3ManagerResult(
        _ result: ChromeMV3ExtensionManagerActionResult
    ) {
        statusMessage = (
            result.diagnostics.first
                ?? result.blockedDiagnostics.first?.message
                ?? result.status.rawValue
        )
        if result.action == .uninstall && result.succeeded {
            chromeMV3ManagerDetailViewModel = nil
        }
        refreshChromeMV3Manager()
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
        extensionManager: ExtensionManager,
        installedExtensions: [InstalledExtension]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Extensions",
                subtitle: extensionManager.extensionsLoaded
                    ? "Sumi is using the WebKit WebExtension backend"
                    : "The WebKit extension runtime is idle"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(extensionManager.isExtensionSupportAvailable
                         ? "Extension installation is disabled while Sumi’s future Chrome MV3 runtime is being designed."
                         : "WebKit extensions require macOS 15.5 or newer in this Sumi build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection(
                title: "Installed Extensions",
                subtitle: installedExtensions.isEmpty
                    ? "No extensions are installed"
                    : "Manage enabled state and uninstall installed extensions"
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
                                isBusy: busyExtensionIDs.contains(ext.id),
                                onToggleEnabled: {
                                    toggleExtension(ext)
                                },
                                onUninstall: {
                                    extensionPendingRemoval = ext
                                }
                            )
                        }
                    }
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

                Text(extensionRecord.isEnabled ? "Enabled in Sumi’s extension runtime" : "Installed but currently disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(extensionRecord.sourceBundlePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(extensionRecord.sourceBundlePath, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy source path")

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

