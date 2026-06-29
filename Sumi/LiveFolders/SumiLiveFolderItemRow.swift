import SwiftUI

struct SumiLiveFolderItemRow: View {
    let item: SumiLiveFolderItem
    let isSelected: Bool
    let accessibilityID: String
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    let onDismiss: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false
    @State private var isDismissHovered = false

    var body: some View {
        HStack(spacing: 0) {
            rowIcon
                .padding(.leading, SidebarRowLayout.leadingInset)
                .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)

            titleStack
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            dismissButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .sidebarRowSurface(
            background: backgroundColor,
            cornerRadius: sumiSettings.resolvedCornerRadius(12),
            tokens: tokens,
            isVisible: isSelected || displayIsHovering,
            drawsSelectionShadow: isSelected
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isSelected ? "selected" : "not selected")
        .sidebarDDGHover($isRowHovered, isEnabled: true)
        .sidebarZenPressEffect(sourceID: accessibilityID, isEnabled: true)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: true,
            primaryAction: action,
            sourceID: accessibilityID,
            entries: contextMenuEntries
        )
    }

    private var rowIcon: some View {
        Image(systemName: item.iconSystemName ?? "link")
            .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(textColor)
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
            .accessibilityHidden(true)
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            SumiTabTitleLabel(
                title: item.title,
                font: .systemFont(ofSize: 13, weight: .medium),
                textColor: textColor,
                trailingPadding: SidebarHoverChrome.trailingPadding(showsTrailingAction: showsDismissButton),
                animated: false
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -1)
            }
        }
        .frame(height: SidebarRowLayout.titleHeight, alignment: .center)
    }

    @ViewBuilder
    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(textColor)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(displayIsDismissHovering ? actionBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(SidebarZenActionButtonStyle(isEnabled: showsDismissButton))
        .opacity(showsDismissButton ? 1 : 0)
        .allowsHitTesting(showsDismissButton)
        .accessibilityHidden(!showsDismissButton)
        .accessibilityLabel("Hide Live Folder Item")
        .sidebarDDGHover($isDismissHovered, isEnabled: showsDismissButton)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsDismissButton,
            isInteractionEnabled: true,
            action: onDismiss
        )
    }

    private var backgroundColor: Color {
        if isSelected {
            return tokens.sidebarRowActive
        }
        if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var textColor: Color {
        tokens.primaryText
    }

    private var actionBackground: Color {
        isSelected ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    private var showsDismissButton: Bool {
        displayIsHovering
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var displayIsDismissHovering: Bool {
        SidebarHoverChrome.displayHover(
            isDismissHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }
}
