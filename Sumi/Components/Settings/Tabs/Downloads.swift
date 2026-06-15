import AppKit
import SwiftUI

struct SettingsDownloadsTab: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var applicationsRevision = 0

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Downloads",
                subtitle: "Choose where downloaded files are saved."
            ) {
                SettingsRow(
                    title: "Save files to",
                    subtitle: settings.downloadsDirectoryDisplayName
                ) {
                    Button("Choose...") {
                        chooseDownloadsFolder()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Always ask you where to save files",
                    subtitle: "Show the save panel for each download destination."
                ) {
                    Toggle("", isOn: $settings.downloadsAlwaysAskWhereToSave)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(
                title: "Applications",
                subtitle: "Choose how downloaded file types are handled."
            ) {
                SettingsRow(
                    title: "What should Sumi do with other files?",
                    subtitle: "Used only when no content-type rule exists."
                ) {
                    Picker("", selection: $settings.downloadsFallbackAction) {
                        ForEach(SumiDownloadFallbackAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .settingsTrailingControl(width: 240)
                }

                let records = sumiSettings.downloadApplicationsStore.records
                if records.isEmpty {
                    SettingsDivider()
                    SettingsEmptyState(
                        systemImage: "doc",
                        title: "No Application Rules",
                        detail: "Rules appear here after you save a choice from a download prompt."
                    )
                } else {
                    SettingsDivider()
                    applicationsHeader
                    ForEach(records) { record in
                        applicationRow(record)
                        if record.id != records.last?.id {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
        .id(applicationsRevision)
    }

    private var applicationsHeader: some View {
        HStack(spacing: 12) {
            Text("Content Type")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Action")
                .frame(width: 220, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func applicationRow(_ record: SumiContentHandlerRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(record.contentType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: handlerBinding(for: record)) {
                ForEach(SumiContentHandlerKind.allCases) { handler in
                    Text(handler.title).tag(handler)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .settingsTrailingControl(width: 220)

            Button {
                sumiSettings.downloadApplicationsStore.remove(contentType: record.contentType)
                applicationsRevision += 1
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove rule")
        }
    }

    private func handlerBinding(for record: SumiContentHandlerRecord) -> Binding<SumiContentHandlerKind> {
        Binding(
            get: {
                sumiSettings.downloadApplicationsStore.record(for: record.contentType)?.handler ?? record.handler
            },
            set: { newValue in
                var updated = record
                updated.handler = newValue
                if newValue == .useOtherApplication {
                    guard let applicationURL = chooseApplication() else { return }
                    updated.applicationURL = applicationURL
                } else {
                    updated.applicationURL = nil
                }
                sumiSettings.downloadApplicationsStore.upsert(updated)
                applicationsRevision += 1
            }
        )
    }

    private func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = sumiSettings.resolvedDownloadsDirectoryURL()
            ?? DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sumiSettings.setDownloadsDirectory(url)
    }

    private func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Use"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

