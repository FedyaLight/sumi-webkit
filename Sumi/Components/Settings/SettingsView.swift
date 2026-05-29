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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionCard(
                title: "Export & Recovery",
                subtitle: "Sumi keeps local SwiftData snapshots and backup directories for recovery"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsActionRow(
                        title: "Sumi data folder",
                        subtitle: "Open the app-support directory that contains runtime stores and backups.",
                        systemImage: "folder",
                        buttonTitle: "Reveal"
                    ) {
                        guard let support = FileManager.default.urls(
                            for: .applicationSupportDirectory,
                            in: .userDomainMask
                        ).first else { return }
                        let bundleId = SumiAppIdentity.runtimeBundleIdentifier
                        let target = support.appendingPathComponent(bundleId, isDirectory: true)
                        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }

                    Text("Direct profile export is still limited, but Sumi’s runtime store and backups now live in their own app-support path.")
                        .font(.caption)
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
        panel.prompt = "Load Unpacked"
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
        panel.prompt = "Inspect"
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
            SettingsSectionCard(
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

            SettingsSectionCard(
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
    @State private var selectedProfileID: UUID? = nil
    @State private var profileEditorPresentation: ProfileEditorPresentation?
    @State private var profilePendingDeletion: Profile?

    var body: some View {
        SettingsSectionCard(
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
        .onAppear(perform: reconcileSelectedProfile)
        .onChange(of: profileIDs) { _, _ in
            reconcileSelectedProfile()
        }
        .sheet(item: $profileEditorPresentation) { presentation in
            profileEditorSheet(for: presentation)
                .environment(\.resolvedThemeContext, profileEditorThemeContext)
                .environment(\.colorScheme, profileEditorColorScheme)
                .preferredColorScheme(profileEditorColorScheme)
        }
        .confirmationDialog(
            "Delete Profile?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button("Delete Profile", role: .destructive) {
                confirmDelete(profile)
            }

            Button("Cancel", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text(deleteConfirmationMessage(for: profile))
        }
    }

    // MARK: - Helpers
    private var profileIDs: [UUID] {
        browserManager.profileManager.profiles.map(\.id)
    }

    private var selectedProfile: Profile? {
        guard let selectedProfileID else { return nil }
        return browserManager.profileManager.profiles.first {
            $0.id == selectedProfileID
        }
    }

    private var profileEditorThemeContext: ResolvedThemeContext {
        themeContext.nativeSurfaceThemeContext
    }

    private var profileEditorColorScheme: ColorScheme {
        profileEditorThemeContext.nativeSurfaceColorScheme
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: {
                profilePendingDeletion != nil
            },
            set: { isPresented in
                if !isPresented {
                    profilePendingDeletion = nil
                }
            }
        )
    }

    private var profileRows: some View {
        VStack(spacing: 0) {
            ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                ProfileRowView(
                    profile: profile,
                    isSelected: selectedProfileID == profile.id,
                    spacesCount: spacesCount(for: profile),
                    tabsCount: tabsCount(for: profile),
                    canDelete: canDelete(profile),
                    onSelect: { selectedProfileID = profile.id },
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
        HStack(spacing: 8) {
            Button("Add Profile...") {
                profileEditorPresentation = .add
            }
            .buttonStyle(.bordered)

            Button("Remove Profile...", role: .destructive) {
                deleteSelectedProfile()
            }
            .buttonStyle(.bordered)
            .disabled(selectedProfile.map(canDelete) != true)

            Spacer(minLength: 0)
        }
    }

    private func reconcileSelectedProfile() {
        if let selectedProfileID,
           browserManager.profileManager.profiles.contains(where: { $0.id == selectedProfileID })
        {
            return
        }

        selectedProfileID = browserManager.profileManager.profiles.first?.id
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
        selectedProfileID = profile.id
        profileEditorPresentation = .edit(profile.id)
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        startDelete(selectedProfile)
    }

    private func startDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }
        selectedProfileID = profile.id
        profilePendingDeletion = profile
    }

    private func createProfile(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isProfileNameAvailable(trimmed) else { return }

        let created = browserManager.profileManager.createProfile(
            name: trimmed,
            icon: SumiProfileIcon.storedValue(icon)
        )
        selectedProfileID = created.id
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
        selectedProfileID = profile.id
        profileEditorPresentation = nil
    }

    private func confirmDelete(_ profile: Profile) {
        guard canDelete(profile) else { return }
        browserManager.deleteProfile(profile)
        profilePendingDeletion = nil
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
        SettingsSection(title: title, subtitle: subtitle) {
            content
        }
    }
}

// MARK: - Site Search Settings

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

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let saved = SiteSearchEntry(
                        id: entry?.id ?? UUID(),
                        name: trimmedName,
                        domain: trimmedDomain,
                        searchURLTemplate: trimmedSearchURLTemplate,
                        colorHex: normalizedColorHex
                    )
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil)
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSearchURLTemplate: String {
        searchURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedColorHex: String {
        let trimmed = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }

    private var validationMessage: String? {
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard !trimmedDomain.isEmpty else { return "Domain is required." }
        guard trimmedSearchURLTemplate.contains("{query}") else {
            return "Search URL must contain {query} where the query should go."
        }
        let sampleTemplate = normalizedURLTemplate(trimmedSearchURLTemplate)
        let sample = sampleTemplate.replacingOccurrences(of: "{query}", with: "sumi")
        guard let url = URL(string: sample),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            return "Enter a valid http or https search URL."
        }
        guard isValidHexColor(normalizedColorHex) else {
            return "Color must be a 3, 6, or 8 digit hex value."
        }
        return nil
    }

    private func normalizedURLTemplate(_ template: String) -> String {
        if template.hasPrefix("http://") || template.hasPrefix("https://") {
            return template
        }
        return "https://\(template)"
    }

    private func isValidHexColor(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard [3, 6, 8].contains(trimmed.count) else { return false }
        return trimmed.allSatisfy(\.isHexDigit)
    }
}
