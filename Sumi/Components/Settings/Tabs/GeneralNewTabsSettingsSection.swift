import SumiDomain
import SwiftUI

struct GeneralNewTabsSettingsSection: View {
    @Binding private var mode: SumiNewTabMode
    @Binding private var pageURLString: String
    @Binding private var openBookmarksAndHistoryInNewTab: Bool

    init(
        mode: Binding<SumiNewTabMode>,
        pageURLString: Binding<String>,
        openBookmarksAndHistoryInNewTab: Binding<Bool>
    ) {
        _mode = mode
        _pageURLString = pageURLString
        _openBookmarksAndHistoryInNewTab = openBookmarksAndHistoryInNewTab
    }

    var body: some View {
        SettingsSection(title: "New Tabs") {
            SettingsRow(
                title: "Open new tabs with",
                systemImage: "plus.square"
            ) {
                Picker("", selection: $mode) {
                    ForEach(SumiNewTabMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .settingsMenuPicker(width: 160)
            }

            if mode == .specificPage {
                SettingsDivider()

                SettingsRow(title: "New Tab URL", systemImage: "link") {
                    TextField("https://example.com", text: $pageURLString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                if let message = SumiNewTabPageURL.validationMessage(for: pageURLString) {
                    SettingsDivider()

                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsDivider()

            SettingsRow(
                title: "Open History and Bookmarks in a new tab",
                subtitle: "Links from History and Bookmarks open in a new tab instead of replacing the current page.",
                systemImage: "plus.rectangle.on.rectangle"
            ) {
                Toggle("", isOn: $openBookmarksAndHistoryInNewTab)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}
