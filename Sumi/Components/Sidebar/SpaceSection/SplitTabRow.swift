import SwiftUI

struct SplitTabRow: View {
    let left: Tab
    let right: Tab
    let spaceId: UUID
    let isAppKitInteractionEnabled: Bool
    let contextMenuEntries: (Tab) -> [SidebarContextMenuEntry]

    let onActivate: (Tab) -> Void
    let onClose: (Tab) -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        HStack(spacing: 1) {
            SplitHalfTab(
                tab: left,
                spaceId: spaceId,
                isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                contextMenuEntries: contextMenuEntries(left),
                onActivate: { onActivate(left) },
                onClose: { onClose(left) },
                isSplitActiveSide: splitManager.activeSide(for: windowState.id) == .left
            )
            Rectangle()
                .fill(tokens.separator)
                .frame(width: 1, height: 24)
                .padding(.vertical, 4)
            SplitHalfTab(
                tab: right,
                spaceId: spaceId,
                isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                contextMenuEntries: contextMenuEntries(right),
                onActivate: { onActivate(right) },
                onClose: { onClose(right) },
                isSplitActiveSide: splitManager.activeSide(for: windowState.id) == .right
            )
        }
        .frame(height: 34)
        .padding(2)
        .background(tokens.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.separator.opacity(0.75), lineWidth: 0.5)
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

private struct SplitHalfTab: View {
    @ObservedObject var tab: Tab
    let spaceId: UUID
    let isAppKitInteractionEnabled: Bool
    let contextMenuEntries: [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onClose: () -> Void
    let isSplitActiveSide: Bool

    @State private var isRowHovered = false
    @State private var isCloseHovered = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                SidebarTabFaviconView(tab: tab, size: 18, cornerRadius: 4)
                SumiTabTitleLabel(
                    title: tab.name,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: textTab,
                    trailingFadePadding: SidebarHoverChrome.trailingFadePadding(
                        showsTrailingAction: displayIsHovering
                    ),
                    isLoading: tab.isLoading
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
            .sidebarAppKitContextMenu(
                isInteractionEnabled: isAppKitInteractionEnabled,
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(
                        tabId: tab.id,
                        title: tab.name,
                        urlString: tab.url.absoluteString
                    ),
                    sourceZone: .spaceRegular(spaceId),
                    previewKind: .row,
                    previewIcon: tab.favicon,
                    exclusionZones: [.trailingStrip(40)],
                    onActivate: onActivate,
                    isEnabled: isAppKitInteractionEnabled
                ),
                primaryAction: onActivate,
                sourceID: rowSourceID,
                entries: { contextMenuEntries }
            )

            closeButton
                .padding(.trailing, 8)
        }
        .opacity(
            SidebarDragState.shared.isDragging && SidebarDragState.shared.activeDragItemId == tab.id
                ? 0.001
                : 1
        )
        .task(id: tab.url) {
            await tab.fetchFaviconForVisiblePresentation()
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .sidebarZenPressEffect(
            sourceID: rowSourceID,
            kind: .split,
            isEnabled: isAppKitInteractionEnabled
        )
        .shadow(
            color: (isSplitActiveSide || isActive) ? tokens.sidebarSelectionShadow : .clear,
            radius: (isSplitActiveSide || isActive) ? 2 : 0,
            y: (isSplitActiveSide || isActive) ? 1 : 0
        )
    }

    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private var rowSourceID: String {
        "space-split-tab-\(tab.id.uuidString)"
    }

    private var backgroundColor: Color {
        if isSplitActiveSide || isActive {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        tokens.primaryText
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(isRowHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsCloseHovering: Bool {
        SidebarHoverChrome.displayHover(isCloseHovered, freezesHoverState: freezesHoverState)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(textTab)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(
                    displayIsCloseHovering
                        ? (isActive
                            ? tokens.fieldBackgroundHover
                            : tokens.fieldBackground)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: displayIsHovering && !freezesHoverState
            )
        )
        .opacity(displayIsHovering ? 1 : 0)
        .sidebarZenActionOpacity(displayIsHovering)
        .allowsHitTesting(displayIsHovering && !freezesHoverState)
        .accessibilityHidden(!displayIsHovering)
        .sidebarDDGHover($isCloseHovered, isEnabled: displayIsHovering && isAppKitInteractionEnabled)
        .accessibilityIdentifier("space-split-tab-close-\(tab.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isEnabled: displayIsHovering && !freezesHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: onClose
        )
    }

}
