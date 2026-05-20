import SwiftUI

struct SplitGroupSidebarRow: View {
    let group: SplitGroup
    let tabs: [Tab]
    let spaceId: UUID
    let isAppKitInteractionEnabled: Bool
    let contextMenuEntries: (Tab) -> [SidebarContextMenuEntry]
    let onActivate: (Tab) -> Void
    let onClose: (Tab) -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                SplitGroupSegment(
                    tab: tab,
                    spaceId: spaceId,
                    isActive: currentTabId == tab.id,
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                    contextMenuEntries: splitContextMenuEntries(for: tab),
                    onActivate: { onActivate(tab) },
                    onClose: { onClose(tab) }
                )
                if index < tabs.count - 1 {
                    Rectangle()
                        .fill(tokens.separator.opacity(0.7))
                        .frame(width: 1, height: 22)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity)
        .padding(.horizontal, 2)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(8), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(8), style: .continuous)
                .stroke(tokens.separator.opacity(displayIsHovering ? 0.9 : 0.45), lineWidth: 0.5)
        }
        .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .accessibilityIdentifier("space-split-group-\(group.id.uuidString)")
    }

    private var background: Color {
        if let currentTabId, group.contains(currentTabId) {
            return tokens.sidebarRowActive
        }
        if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return tokens.fieldBackground.opacity(0.65)
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var currentTabId: UUID? {
        browserManager.currentTab(for: windowState)?.id
    }

    private func splitContextMenuEntries(for tab: Tab) -> [SidebarContextMenuEntry] {
        var entries = contextMenuEntries(tab)
        let splitEntries: [SidebarContextMenuEntry] = [
            .submenu(
                title: "Split Layout",
                systemImage: "rectangle.split.2x2",
                children: [
                    .action(.init(title: "Grid", systemImage: "square.grid.2x2", onAction: {
                        splitManager.setLayoutKind(.grid, for: windowState.id)
                    })),
                    .action(.init(title: "Vertical", systemImage: "rectangle.split.2x1", onAction: {
                        splitManager.setLayoutKind(.vertical, for: windowState.id)
                    })),
                    .action(.init(title: "Horizontal", systemImage: "rectangle.split.1x2", onAction: {
                        splitManager.setLayoutKind(.horizontal, for: windowState.id)
                    }))
                ]
            ),
            .submenu(
                title: "New Empty Split",
                systemImage: "plus.rectangle.on.rectangle",
                children: [
                    .action(.init(title: "Right", systemImage: "rectangle.righthalf.filled", onAction: {
                        splitManager.createEmptySplit(side: .right, in: windowState)
                    })),
                    .action(.init(title: "Left", systemImage: "rectangle.lefthalf.filled", onAction: {
                        splitManager.createEmptySplit(side: .left, in: windowState)
                    })),
                    .action(.init(title: "Top", systemImage: "rectangle.tophalf.filled", onAction: {
                        splitManager.createEmptySplit(side: .top, in: windowState)
                    })),
                    .action(.init(title: "Bottom", systemImage: "rectangle.bottomhalf.filled", onAction: {
                        splitManager.createEmptySplit(side: .bottom, in: windowState)
                    })),
                ]
            ),
            .action(.init(title: "Unsplit", systemImage: "rectangle", onAction: {
                splitManager.unsplitActiveGroup(for: windowState.id)
            }))
        ]
        entries.append(.separator)
        entries.append(contentsOf: splitEntries)
        return entries
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

private struct SplitGroupSegment: View {
    @ObservedObject var tab: Tab
    let spaceId: UUID
    let isActive: Bool
    let isAppKitInteractionEnabled: Bool
    let contextMenuEntries: [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                SidebarTabFaviconView(tab: tab, size: 16, cornerRadius: 4)
                SumiTabTitleLabel(
                    title: tab.name,
                    font: .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular),
                    textColor: tokens.primaryText,
                    trailingFadePadding: displayIsHovering ? 2 : 0,
                    isLoading: tab.isLoading
                )
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 7)
            .padding(.trailing, displayIsHovering ? 28 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .sidebarDDGHover($isHovered, isEnabled: isAppKitInteractionEnabled)
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
                    exclusionZones: [.trailingStrip(32)],
                    onActivate: onActivate,
                    isEnabled: isAppKitInteractionEnabled
                ),
                primaryAction: onActivate,
                sourceID: rowSourceID,
                entries: { contextMenuEntries }
            )

            closeButton
                .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(6), style: .continuous)
                .fill(isActive ? tokens.sidebarRowActive.opacity(0.9) : (displayIsHovering ? tokens.sidebarRowHover : Color.clear))
        )
        .task(id: tab.url) {
            await tab.fetchFaviconForVisiblePresentation()
        }
    }

    private var rowSourceID: String {
        "space-split-tab-\(tab.id.uuidString)"
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var displayIsCloseHovering: Bool {
        SidebarHoverChrome.displayHover(
            isCloseHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tokens.primaryText)
                .frame(width: 20, height: 20)
                .background(displayIsCloseHovering ? tokens.fieldBackgroundHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: displayIsHovering && !windowState.sidebarInteractionState.freezesSidebarHoverState
            )
        )
        .opacity(displayIsHovering ? 1 : 0)
        .sidebarZenActionOpacity(displayIsHovering)
        .allowsHitTesting(displayIsHovering && !windowState.sidebarInteractionState.freezesSidebarHoverState)
        .sidebarDDGHover($isCloseHovered, isEnabled: displayIsHovering && isAppKitInteractionEnabled)
        .accessibilityIdentifier("space-split-tab-close-\(tab.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isEnabled: displayIsHovering && !windowState.sidebarInteractionState.freezesSidebarHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: onClose
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
