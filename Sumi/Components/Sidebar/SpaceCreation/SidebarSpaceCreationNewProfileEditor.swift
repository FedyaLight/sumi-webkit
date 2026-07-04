import SwiftUI

struct SidebarSpaceCreationNewProfileEditor: View {
    @ObservedObject var session: SpaceCreationSession
    let validationMessage: String?
    let focusedField: FocusState<SidebarSpaceCreationFocusedField?>.Binding
    let tokens: ChromeThemeTokens
    let iconCornerRadius: CGFloat
    let onSubmit: () -> Void

    @StateObject private var emojiManager = EmojiPickerManager()
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        VStack(spacing: 0) {
            nameRow

            if let validationMessage {
                validationRow(validationMessage)
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Button(action: openEmojiPicker) {
                SumiProfileIconView(
                    icon: session.resolvedNewProfileIcon,
                    font: SidebarSpaceCreationThemeTokens.Typography.profileIcon
                )
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )
                .background(tokens.chromeControlHoverBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(EmojiPickerAnchor(manager: emojiManager))
            .help("Choose Profile Icon")
            .accessibilityLabel("Choose Profile Icon")

            TextField("Profile name", text: $session.newProfileName)
                .textFieldStyle(.plain)
                .font(SidebarSpaceCreationThemeTokens.Typography.rowLabel)
                .foregroundStyle(tokens.primaryText)
                .focused(focusedField, equals: .newProfileName)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("sidebar-space-creation-new-profile-name")
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarSpaceCreationMetrics.formRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func validationRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: 1
                )

            Text(message)
                .font(SidebarSpaceCreationThemeTokens.Typography.validation)
                .foregroundStyle(SidebarSpaceCreationThemeTokens.Colors.validationText)
                .lineLimit(1)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openEmojiPicker() {
        emojiManager.selectedEmoji = session.resolvedNewProfileIcon
        emojiManager.toggle(
            settings: sumiSettings,
            themeContext: themeContext
        ) { picked in
            let trimmed = picked.trimmingCharacters(in: .whitespacesAndNewlines)
            session.newProfileIcon = trimmed.isEmpty
                ? SpaceCreationSession.defaultProfileIcon
                : SumiProfileIcon.storedValue(trimmed)
        }
    }
}
