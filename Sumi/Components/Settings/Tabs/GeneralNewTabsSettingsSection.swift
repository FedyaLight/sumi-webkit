import SumiDomain
import SwiftUI

struct GeneralNewTabsSettingsSection: View {
    @Binding private var mode: SumiNewTabMode
    @Binding private var pageURLString: String

    init(
        mode: Binding<SumiNewTabMode>,
        pageURLString: Binding<String>
    ) {
        _mode = mode
        _pageURLString = pageURLString
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
        }
    }
}
