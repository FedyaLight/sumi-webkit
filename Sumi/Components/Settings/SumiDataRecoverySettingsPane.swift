//
//  SumiDataRecoverySettingsPane.swift
//  Sumi
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct SumiDataRecoveryActions {
    let importBookmarksFromMenu: () -> Void
    let writeZenBackup: (URL) async throws -> Void
    let writeBackup: (URL) throws -> Void
    let applyImport: (SumiImportRequest) async throws -> SumiImportReport
}

struct SumiDataRecoverySettingsPane: View {
    private static let log = Logger.sumi(category: "DataRecovery")

    let actions: SumiDataRecoveryActions
    @State private var importPreview: SumiImportPreview?
    @State private var selectedCategories: Set<SumiImportCategory> = []
    @State private var applyMode: SumiImportApplyMode = .merge
    @State private var statusMessage: String?
    @State private var isWorking = false
    @State private var previewTask: Task<Void, Never>?
    @State private var previewGeneration: UInt64 = 0
    @State private var isWizardPresented = false

    private let importService = SumiBrowserImportService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Browser Import",
                subtitle: "Bring spaces, launchers, tabs, folders, themes, profiles, and bookmarks into Sumi."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsActionRow(
                        title: "Import from another browser",
                        subtitle: "Bring spaces, pinned items, open tabs, folders, themes, and bookmarks "
                            + "from Arc, Zen, Chrome, Edge, Brave, Firefox, Safari, and other installed browsers.",
                        systemImage: "arrow.down.circle",
                        buttonTitle: "Import"
                    ) {
                        isWizardPresented = true
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
                subtitle: "Move your browser data to Zen or create a logical Sumi backup."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsActionRow(
                        title: "Export for Zen",
                        subtitle: "Create a browser2zen .zenbackup with workspaces, tabs, folders, bookmarks, history, and cookies.",
                        systemImage: "arrow.up.doc",
                        buttonTitle: "Export"
                    ) {
                        exportForZen()
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
        .sheet(isPresented: $isWizardPresented) {
            SumiImportWizardSheet(
                actions: SumiImportWizardActions(
                    detectSources: { await importService.detectSources() },
                    preparePreview: { try await importService.preview($0) },
                    applyImport: actions.applyImport
                ),
                onClose: { isWizardPresented = false }
            )
            .sumiNativeSurfaceColorScheme()
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
                .sumiNativeSurfaceColorScheme()
            }
        }
        .onDisappear {
            previewGeneration &+= 1
            previewTask?.cancel()
            previewTask = nil
            isWorking = false
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

    private func loadPreview(
        _ operation: @escaping @MainActor @Sendable () async throws -> SumiImportPreview
    ) {
        previewTask?.cancel()
        previewGeneration &+= 1
        let generation = previewGeneration
        isWorking = true
        statusMessage = nil
        previewTask = Task { @MainActor in
            defer {
                if previewGeneration == generation {
                    isWorking = false
                    previewTask = nil
                }
            }
            do {
                let preview = try await operation()
                guard !Task.isCancelled, previewGeneration == generation else { return }
                importPreview = preview
                selectedCategories = preview.suggestedCategories
                applyMode = preview.defaultMode
            } catch is CancellationError {
                return
            } catch {
                guard previewGeneration == generation else { return }
                statusMessage = error.localizedDescription
            }
        }
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
            try await withSecurityScoped(url) {
                try await importService.previewFileImport(fileURL: url)
            }
        }
    }

    private func exportForZen() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zenBackup]
        panel.nameFieldStringValue = "Sumi-\(Self.backupDateStamp()).zenbackup"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        statusMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await withSecurityScoped(url) {
                    try await actions.writeZenBackup(url)
                }
                statusMessage = "Exported \(url.lastPathComponent)."
            } catch {
                statusMessage = error.localizedDescription
            }
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
                try actions.writeBackup(url)
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
                let result = try await actions.applyImport(SumiImportRequest(
                    sourceKind: importPreview.sourceKind,
                    data: importPreview.data,
                    categories: selectedCategories,
                    mode: applyMode
                ))
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
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            Self.log.error(
                "Failed to create data recovery folder at \(target.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            statusMessage = "Could not reveal data folder: \(error.localizedDescription)"
            return
        }
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

    private func withSecurityScoped<T: Sendable>(
        _ url: URL,
        operation: () async throws -> T
    ) async rethrows -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
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

            if applyMode == .replace,
               selectedCategories.contains(.profiles) {
                Label(
                    "Replace safely retires local profiles not present in the import "
                        + "and removes their profile-scoped website data, which is not "
                        + "included in backups.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
