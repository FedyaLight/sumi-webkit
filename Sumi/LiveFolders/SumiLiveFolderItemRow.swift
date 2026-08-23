import SwiftUI

struct SumiLiveFolderItemRow: View {
    let item: SumiLiveFolderItem
    let shortcutPin: ShortcutPin?
    let faviconPartition: SumiFaviconPartition?
    let faviconImageReader: (any BrowserFaviconImageReading)?
    let folderID: UUID
    let isSelected: Bool
    let isInteractionEnabled: Bool
    let accessibilityID: String
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    let onDismiss: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isRowHovered = false
    @State private var isDismissHovered = false
    @Environment(SidebarFaviconImageStore.self) private var faviconImageStore

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
        .sidebarHover($isRowHovered, isEnabled: isInteractionEnabled)
        .sidebarZenPressEffect(sourceID: accessibilityID)
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isInteractionEnabled,
            dragSource: dragSourceConfiguration,
            primaryActionExclusionZones: [.trailingStrip(40)],
            releaseAction: action,
            sourceID: accessibilityID,
            entries: contextMenuEntries
        )
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
    }

    private var dragSourceConfiguration: SidebarDragSourceConfiguration? {
        guard let shortcutPin else { return nil }
        return SidebarDragSourceConfiguration(
            item: .shortcutPin(
                shortcutPin.id,
                title: item.title,
                urlString: item.urlString
            ),
            sourceZone: .folder(folderID),
            previewKind: .row,
            exclusionZones: [.trailingStrip(40)],
            isEnabled: isInteractionEnabled
        )
    }

    @ViewBuilder
    private var rowIcon: some View {
        Group {
            if isRSSItem, let storedFavicon {
                storedFavicon
                    .resizable()
                    .scaledToFit()
            } else if let bundledIconName {
                SumiZenBundledIconView(
                    image: SumiZenFolderIconCatalog.bundledFolderImage(named: bundledIconName),
                    size: SidebarRowLayout.faviconSize,
                    tint: textColor
                )
            } else {
                Image(systemName: item.iconSystemName ?? "link")
                    .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(textColor)
            }
        }
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
            .accessibilityHidden(true)
    }

    private var bundledIconName: String? {
        guard let icon = item.iconSystemName,
              icon.hasPrefix(SumiZenFolderIconCatalog.folderValuePrefix) else {
            return nil
        }
        return String(icon.dropFirst(SumiZenFolderIconCatalog.folderValuePrefix.count))
    }

    private var isRSSItem: Bool {
        bundledIconName == "logo-rss"
    }

    private var storedFavicon: Image? {
        guard let shortcutPin, let faviconPartition else { return nil }
        return faviconImageStore.image(
            for: shortcutPin.launchURL,
            partition: faviconPartition,
            context: .tabSidebar
        )
    }

    private var storedFaviconLoadKey: String {
        guard isRSSItem,
              let shortcutPin,
              let faviconPartition else {
            return "disabled|\(item.id)"
        }
        return faviconImageStore.loadKey(
            launchURL: shortcutPin.launchURL,
            partition: faviconPartition,
            context: .tabSidebar
        )
    }

    private func loadStoredFavicon() async {
        guard isRSSItem,
              let shortcutPin,
              let faviconPartition,
              let faviconImageReader else { return }
        await faviconImageStore.load(
            launchURL: shortcutPin.launchURL,
            partition: faviconPartition,
            context: .tabSidebar,
            imageReader: faviconImageReader
        )
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            SumiTabTitleLabel(
                title: item.title,
                font: SidebarThemeTokens.Typography.rowTitle,
                textColor: textColor,
                reservedTrailingWidth: showsDismissButton ? SidebarRowLayout.trailingActionPadding : 0,
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
        .sidebarHover($isDismissHovered, isEnabled: showsDismissButton)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsDismissButton,
            isInteractionEnabled: isInteractionEnabled,
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
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
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
        isRowHovered
    }

    private var displayIsDismissHovering: Bool {
        isDismissHovered
    }
}
