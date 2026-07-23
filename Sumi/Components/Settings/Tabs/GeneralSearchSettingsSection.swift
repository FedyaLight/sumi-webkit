import SwiftUI

struct GeneralSearchEngineChoice: Identifiable, Equatable {
    let id: String
    let name: String

    init(_ engine: SumiSearchEngine) {
        id = engine.id
        name = engine.name
    }
}

struct GeneralSearchSettingsSection: View {
    @Binding private var emptyStateMode: CommandPaletteEmptyStateMode
    @Binding private var defaultEngineID: String
    let engineChoices: [GeneralSearchEngineChoice]

    init(
        emptyStateMode: Binding<CommandPaletteEmptyStateMode>,
        defaultEngineID: Binding<String>,
        engineChoices: [GeneralSearchEngineChoice]
    ) {
        _emptyStateMode = emptyStateMode
        _defaultEngineID = defaultEngineID
        self.engineChoices = engineChoices
    }

    var body: some View {
        SettingsSection(
            title: "Search",
            subtitle: "Choose the default web search and how the command palette behaves before typing."
        ) {
            SettingsRow(
                title: "Command palette empty state",
                subtitle: "Choose what appears before you start typing."
            ) {
                Picker("", selection: $emptyStateMode) {
                    ForEach(CommandPaletteEmptyStateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .settingsTrailingControl(width: 160)
            }

            SettingsDivider()

            SettingsRow(
                title: "Default search engine",
                subtitle: "Used for plain text typed into the URL bar."
            ) {
                Picker("", selection: $defaultEngineID) {
                    ForEach(engineChoices) { engine in
                        Text(engine.name).tag(engine.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .settingsTrailingControl(width: 210)
            }
        }
    }
}
