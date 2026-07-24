//
//  General.swift
//  Sumi
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) private var sumiSettings
    let defaultBrowserService: SumiDefaultBrowserService

    var body: some View {
        @Bindable var chrome = sumiSettings.chrome
        @Bindable var search = sumiSettings.search

        VStack(alignment: .leading, spacing: 16) {
            DefaultBrowserSettingsSection(service: defaultBrowserService)

            GeneralWindowSettingsSection(
                askBeforeQuit: $chrome.askBeforeQuit,
                glanceEnabled: $chrome.glanceEnabled
            )

            GeneralNewTabsSettingsSection(
                mode: $chrome.newTabMode,
                pageURLString: $chrome.newTabPageURLString
            )

            GeneralSearchSettingsSection(
                defaultEngineID: $search.searchEngineId,
                engineChoices: search.searchEngines.map(GeneralSearchEngineChoice.init)
            )

            GeneralSearchEnginesSettingsSection(
                searchEngines: $search.searchEngines
            )
        }
    }
}
