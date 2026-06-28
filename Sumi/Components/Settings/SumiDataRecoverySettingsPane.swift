//
//  SumiDataRecoverySettingsPane.swift
//  Sumi
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
