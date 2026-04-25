//
//  General.swift
//  Sumi
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var showingAddSite = false
    @State private var showingAddEngine = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        @Bindable var settings = sumiSettings
        Form {
            Section("Sumi Window") {
                Toggle("Warn before quitting the browser", isOn: $settings.askBeforeQuit)
                Toggle("Preview link URL on hover", isOn: $settings.showLinkStatusBar)
                Toggle("Show Sidebar toggle button", isOn: $settings.showSidebarToggleButton)
                Toggle("Show New Tab button in tab list", isOn: $settings.showNewTabButtonInTabList)

                Picker(
                    "New Tab button position",
                    selection: $settings.tabListNewTabButtonPosition
                ) {
                    ForEach(TabListNewTabButtonPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .disabled(!settings.showNewTabButtonInTabList)
            }

            Section(header: Text("Search")) {
                Text("Sumi keeps one canonical URL bar in the sidebar header and routes search actions through it.")
                    .foregroundStyle(.secondary)

                HStack {
                    Picker(
                        "Default search engine",
                        selection: $settings.searchEngineId
                    ) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                        ForEach(sumiSettings.customSearchEngines) { engine in
                            Text(engine.name).tag(engine.id.uuidString)
                        }
                    }

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

            Section {
                ForEach(sumiSettings.siteSearchEntries) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 10, height: 10)
                        Text(entry.name)
                        Spacer()
                        Text(entry.domain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button {
                            sumiSettings.siteSearchEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }

                Button("Reset to Defaults") {
                    sumiSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                }
            } header: {
                Text("Site Search")
            } footer: {
                Text("Type a prefix in the command palette and press Tab to search a site directly.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.windowBackground)
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
    }
}

// MARK: - Custom Search Engine Editor

struct CustomSearchEngineEditor: View {
    let onSave: (CustomSearchEngine) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlTemplate: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Search Engine")
                .font(.headline)

            Form {
                TextField("Name (e.g. Startpage)", text: $name)
                TextField("URL Template (use %@ for query)", text: $urlTemplate)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let engine = CustomSearchEngine(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(engine)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || urlTemplate.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
    }
}
