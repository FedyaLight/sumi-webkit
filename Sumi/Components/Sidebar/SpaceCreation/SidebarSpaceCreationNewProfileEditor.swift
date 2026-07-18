import SwiftUI

struct SidebarSpaceCreationNewProfileEditor: View {
    @ObservedObject var session: SpaceCreationSession
    let validationMessage: String?
    let focusedField: FocusState<SidebarSpaceCreationFocusedField?>.Binding
    let tokens: ChromeThemeTokens
    let onSubmit: () -> Void

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
            Image(systemName: "person.badge.plus")
                .font(SidebarSpaceCreationThemeTokens.Typography.rowGlyph)
                .foregroundStyle(tokens.secondaryText)
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )
                .accessibilityHidden(true)

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
}
