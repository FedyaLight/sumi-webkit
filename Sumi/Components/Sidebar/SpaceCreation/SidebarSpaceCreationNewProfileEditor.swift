import SwiftUI

private let sidebarSpaceCreationProfileIcons = [
    "person.crop.circle",
    "person.crop.circle.fill",
    "person.2.circle",
    "briefcase",
    "house",
    "sparkles"
]

struct SidebarSpaceCreationNewProfileEditor: View {
    @ObservedObject var session: SpaceCreationSession
    let validationMessage: String?
    let focusedField: FocusState<SidebarSpaceCreationFocusedField?>.Binding
    let tokens: ChromeThemeTokens
    let iconCornerRadius: CGFloat
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            nameRow
            iconPickerRow

            if let validationMessage {
                validationRow(validationMessage)
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Image(systemName: session.resolvedNewProfileIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )

            TextField("Profile name", text: $session.newProfileName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
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

    private var iconPickerRow: some View {
        HStack(spacing: 6) {
            ForEach(sidebarSpaceCreationProfileIcons, id: \.self) { icon in
                SidebarSpaceCreationProfileIconButton(
                    icon: icon,
                    isSelected: session.resolvedNewProfileIcon == icon,
                    tokens: tokens,
                    cornerRadius: iconCornerRadius,
                    onSelect: { session.newProfileIcon = icon }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.bottom, 10)
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarSpaceCreationProfileIconButton: View {
    let icon: String
    let isSelected: Bool
    let tokens: ChromeThemeTokens
    let cornerRadius: CGFloat
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : tokens.secondaryText)
                .frame(width: 28, height: 28)
                .background(backgroundShape)
                .overlay { borderShape }
        }
        .buttonStyle(.plain)
        .help(icon)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color.accentColor.opacity(0.16)
                    : tokens.chromeControlHoverBackground.opacity(0.56)
            )
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isSelected
                    ? Color.accentColor.opacity(0.72)
                    : tokens.separator.opacity(0.24),
                lineWidth: 1
            )
    }
}
