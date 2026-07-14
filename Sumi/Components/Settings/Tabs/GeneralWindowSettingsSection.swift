import SwiftUI

struct GeneralWindowSettingsSection: View {
    @Binding private var askBeforeQuit: Bool
    @Binding private var glanceEnabled: Bool

    init(
        askBeforeQuit: Binding<Bool>,
        glanceEnabled: Binding<Bool>
    ) {
        _askBeforeQuit = askBeforeQuit
        _glanceEnabled = glanceEnabled
    }

    var body: some View {
        SettingsSection(
            title: "Window",
            subtitle: "Core browser-window behavior."
        ) {
            SettingsRow(
                title: "Warn before quitting",
                subtitle: "Ask for confirmation before closing Sumi."
            ) {
                Toggle("", isOn: $askBeforeQuit)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsRow(
                title: "Glance",
                subtitle: "Preview links without fully opening a tab."
            ) {
                Toggle("", isOn: $glanceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}
