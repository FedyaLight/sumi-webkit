import SwiftUI

enum SumiSearchEngineTableLayout {
    static let headerHeight: CGFloat = 30
    static let tabSearchControlCenterTrailingOffset: CGFloat = 99
    static let tabSearchVisualCenterCorrection: CGFloat = 14
    static let rowHeight: CGFloat = 36
    static let intercellSpacing: CGFloat = 1
    static let minimumVisibleRows = 4
    static let footerHeight: CGFloat = 44

    static func tableHeight(engineCount: Int) -> CGFloat {
        let visibleRows = max(engineCount, minimumVisibleRows)
        return headerHeight + CGFloat(visibleRows) * (rowHeight + intercellSpacing) + 2
    }

    static func preferredHeight(engineCount: Int) -> CGFloat {
        tableHeight(engineCount: engineCount) + footerHeight
    }

    static var tabSearchHeaderCenterTrailingOffset: CGFloat {
        tabSearchControlCenterTrailingOffset + tabSearchVisualCenterCorrection
    }
}

struct GeneralSearchEnginesSettingsSection: View {
    @Binding private var searchEngines: [SumiSearchEngine]
    @Binding private var filterText: String

    init(
        searchEngines: Binding<[SumiSearchEngine]>,
        filterText: Binding<String>
    ) {
        _searchEngines = searchEngines
        _filterText = filterText
    }

    var body: some View {
        SettingsSection {
            SumiSearchEngineTable(
                searchEngines: $searchEngines,
                filterText: $filterText
            )
                .frame(minHeight: SumiSearchEngineTableLayout.preferredHeight(
                    engineCount: searchEngines.count
                ))
        }
    }
}

struct GeneralSearchEnginesSettingsNavigationSection: View {
    let action: () -> Void

    var body: some View {
        SettingsSection(title: String(localized: "Search Engines")) {
            SumiSiteSettingsNavigationRow(
                title: String(localized: "Manage Search Engines"),
                subtitle: String(localized: "Add, edit, remove, and reorder search engines."),
                systemImage: "magnifyingglass",
                action: action
            )
        }
    }
}
