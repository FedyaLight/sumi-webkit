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
        SettingsSection(title: "Window") {
            SettingsRow(
                title: "Warn before quitting",
                systemImage: "power"
            ) {
                Toggle("", isOn: $askBeforeQuit)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsRow(
                title: "Glance",
                subtitle: "Preview links without opening a full browser tab.",
                systemImage: "eye"
            ) {
                Toggle("", isOn: $glanceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}
