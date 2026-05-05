//
//  General.swift
//  Sumi
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @State private var showingAddSite = false
    @State private var showingAddEngine = false
    @State private var sitePendingRemoval: SiteSearchEntry?
    @State private var customEnginePendingRemoval: CustomSearchEngine?

    var body: some View {
        @Bindable var settings = sumiSettings

        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Window",
                subtitle: "Core browser-window behavior."
            ) {
                SettingsRow(
                    title: "Warn before quitting",
                    subtitle: "Ask for confirmation before closing Sumi."
                ) {
                    Toggle("", isOn: $settings.askBeforeQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Glance",
                    subtitle: "Preview links without fully opening a tab."
                ) {
                    Toggle("", isOn: $settings.glanceEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(
                title: "Search",
                subtitle: "Sumi routes searches through the canonical URL bar in the sidebar header."
            ) {
                SettingsRow(
                    title: "Default search engine",
                    subtitle: "Used for plain text typed into the URL bar."
                ) {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.searchEngineId) {
                            ForEach(SearchProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                            ForEach(sumiSettings.customSearchEngines) { engine in
                                Text(engine.name).tag(engine.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)

                        Button {
                            showingAddEngine = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Add custom search engine")
                    }
                }

                if let selected = selectedCustomSearchEngine {
                    SettingsDivider()

                    SettingsActionRow(
                        title: selected.name,
                        systemImage: "magnifyingglass",
                        buttonTitle: "Remove",
                        role: .destructive
                    ) {
                        customEnginePendingRemoval = selected
                    }
                }
            }

            SettingsSection(
                title: "Site Search",
                subtitle: "Type a site prefix in the command palette, then press Tab to search that site."
            ) {
                if sumiSettings.siteSearchEntries.isEmpty {
                    SettingsEmptyState(
                        systemImage: "globe.badge.chevron.backward",
                        title: "No Site Searches",
                        detail: "Add a site search to jump directly into a website search field."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sumiSettings.siteSearchEntries) { entry in
                            siteSearchRow(entry)
                        }
                    }
                }

                SettingsDivider()

                HStack(spacing: 8) {
                    Button {
                        showingAddSite = true
                    } label: {
                        Label("Add Site", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to Defaults") {
                        sumiSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                sumiSettings.siteSearchEntries.append(newEntry)
            }
        }
        .sheet(isPresented: $showingAddEngine) {
            CustomSearchEngineEditor { newEngine in
                sumiSettings.customSearchEngines.append(newEngine)
            }
        }
        .confirmationDialog(
            "Remove Custom Search Engine?",
            isPresented: customEngineRemovalBinding
        ) {
            Button("Remove", role: .destructive) {
                removePendingCustomEngine()
            }
            Button("Cancel", role: .cancel) {
                customEnginePendingRemoval = nil
            }
        } message: {
            Text(customEnginePendingRemoval?.name ?? "")
        }
        .confirmationDialog(
            "Remove Site Search?",
            isPresented: siteRemovalBinding
        ) {
            Button("Remove", role: .destructive) {
                removePendingSiteSearch()
            }
            Button("Cancel", role: .cancel) {
                sitePendingRemoval = nil
            }
        } message: {
            Text(sitePendingRemoval?.name ?? "")
        }
    }

    private var selectedCustomSearchEngine: CustomSearchEngine? {
        sumiSettings.customSearchEngines.first {
            $0.id.uuidString == sumiSettings.searchEngineId
        }
    }

    private var customEngineRemovalBinding: Binding<Bool> {
        Binding(
            get: { customEnginePendingRemoval != nil },
            set: { isPresented in
                if !isPresented { customEnginePendingRemoval = nil }
            }
        )
    }

    private var siteRemovalBinding: Binding<Bool> {
        Binding(
            get: { sitePendingRemoval != nil },
            set: { isPresented in
                if !isPresented { sitePendingRemoval = nil }
            }
        )
    }

    private func siteSearchRow(_ entry: SiteSearchEntry) -> some View {
        SettingsRow(
            title: entry.name,
            systemImage: nil
        ) {
            HStack(spacing: 8) {
                Text(entry.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(entry.color)
                    .frame(width: 10, height: 10)

                Button(role: .destructive) {
                    sitePendingRemoval = entry
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help("Remove site search")
            }
        }
    }

    private func removePendingCustomEngine() {
        guard let selected = customEnginePendingRemoval else { return }
        sumiSettings.customSearchEngines.removeAll { $0.id == selected.id }
        if sumiSettings.searchEngineId == selected.id.uuidString {
            sumiSettings.searchEngineId = SearchProvider.google.rawValue
        }
        customEnginePendingRemoval = nil
    }

    private func removePendingSiteSearch() {
        guard let entry = sitePendingRemoval else { return }
        sumiSettings.siteSearchEntries.removeAll { $0.id == entry.id }
        sitePendingRemoval = nil
    }
}

struct CustomSearchEngineEditor: View {
    let onSave: (CustomSearchEngine) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlTemplate = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Search Engine")
                .font(.headline)

            Form {
                TextField("Name (e.g. Startpage)", text: $name)
                TextField("URL Template (use %@ for query)", text: $urlTemplate)

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
                    onSave(
                        CustomSearchEngine(
                            name: trimmedName,
                            urlTemplate: trimmedURLTemplate
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 450)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURLTemplate: String {
        urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard !trimmedName.isEmpty else { return "Name is required." }
        guard trimmedURLTemplate.contains("%@") else {
            return "URL template must contain %@ where the query should go."
        }
        let sample = trimmedURLTemplate.replacingOccurrences(of: "%@", with: "sumi")
        guard let url = URL(string: sample),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            return "Enter a valid http or https URL template."
        }
        return nil
    }
}
