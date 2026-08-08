//
//  General.swift
//  Sumi
//

import SwiftUI

struct SettingsGeneralTab: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @EnvironmentObject private var toolbarOwner: SettingsWindowToolbarOwner
    let defaultBrowserService: SumiDefaultBrowserService

    var body: some View {
        @Bindable var settings = sumiSettings
        @Bindable var search = sumiSettings.search

        Group {
            if settings.generalSettingsRoute.isSearchEngines {
                GeneralSearchEnginesSettingsSection(
                    searchEngines: $search.searchEngines,
                    filterText: searchTextBinding
                )
            } else {
                SettingsGeneralOverview(
                    defaultBrowserService: defaultBrowserService,
                    onOpenSearchEngines: {
                        settings.generalSettingsRoute = .searchEngines
                    }
                )
            }
        }
        .onAppear(perform: updateToolbar)
        .onChange(of: settings.generalSettingsRoute) { _, _ in
            updateToolbar()
        }
    }

    private func updateToolbar() {
        if sumiSettings.generalSettingsRoute.isSearchEngines {
            toolbarOwner.show(
                title: String(localized: "Search Engines"),
                backAction: {
                    sumiSettings.generalSettingsRoute = .overview
                },
                forwardAction: nil,
                searchFieldLabel: String(localized: "Filter Search Engines")
            )
        } else {
            toolbarOwner.show(
                title: String(localized: "General"),
                backAction: nil,
                forwardAction: nil
            )
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { toolbarOwner.searchText },
            set: { toolbarOwner.setSearchText($0) }
        )
    }
}

private struct SettingsGeneralOverview: View {
    @Environment(\.sumiSettings) private var sumiSettings
    let defaultBrowserService: SumiDefaultBrowserService
    let onOpenSearchEngines: () -> Void

    var body: some View {
        @Bindable var chrome = sumiSettings.chrome
        @Bindable var search = sumiSettings.search

        VStack(alignment: .leading, spacing: 20) {
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

            GeneralSearchEnginesSettingsNavigationSection(action: onOpenSearchEngines)
        }
    }
}
