import SwiftUI

enum SumiSearchEngineTableLayout {
    static let rowHeight: CGFloat = 36
    static let intercellSpacing: CGFloat = 1
    static let minimumVisibleRows = 4
    static let chromeHeight: CGFloat = 64

    static func tableHeight(engineCount: Int) -> CGFloat {
        let visibleRows = max(engineCount, minimumVisibleRows)
        return CGFloat(visibleRows) * (rowHeight + intercellSpacing) + 2
    }

    static func preferredHeight(engineCount: Int) -> CGFloat {
        tableHeight(engineCount: engineCount) + chromeHeight
    }
}

struct GeneralSearchEnginesSettingsSection: View {
    @Binding private var searchEngines: [SumiSearchEngine]

    init(searchEngines: Binding<[SumiSearchEngine]>) {
        _searchEngines = searchEngines
    }

    var body: some View {
        SettingsSection(title: String(localized: "Search Engines")) {
            SumiSearchEngineTable(searchEngines: $searchEngines)
                .frame(height: SumiSearchEngineTableLayout.preferredHeight(
                    engineCount: searchEngines.count
                ))
        }
    }
}
