import SwiftUI
import SumiDomain

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
        SettingsSection(
            title: "New Tabs",
            subtitle: "Choose what opens when you create a new tab."
        ) {
            SettingsRow(
                title: "Open new tabs with",
                subtitle: "Choose between the floating bar or a specific page."
            ) {
                Picker("", selection: $mode) {
                    ForEach(SumiNewTabMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .settingsTrailingControl(width: 160)
            }

            if mode == .specificPage {
                SettingsDivider()

                SettingsRow(
                    title: "New Tab URL",
                    subtitle: "Use a full URL or a bare domain."
                ) {
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
