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
    @Binding private var defaultEngineID: String
    let engineChoices: [GeneralSearchEngineChoice]

    init(
        defaultEngineID: Binding<String>,
        engineChoices: [GeneralSearchEngineChoice]
    ) {
        _defaultEngineID = defaultEngineID
        self.engineChoices = engineChoices
    }

    var body: some View {
        SettingsSection(
            title: "Search",
            subtitle: "Choose the default web search engine."
        ) {
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
