import SwiftUI

struct SplitTabRow: View {
    let left: Tab
    let right: Tab
    let spaceId: UUID
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
                side: .left,
                spaceId: spaceId,
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
                side: .right,
                spaceId: spaceId,
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
    let side: SplitViewManager.Side
    let spaceId: UUID
    let contextMenuEntries: [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onClose: () -> Void
    let isSplitActiveSide: Bool

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                SidebarTabFaviconView(tab: tab, size: 18, cornerRadius: 4)
                SumiTabTitleLabel(
                    title: tab.name,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    textColor: textTab,
                    trailingFadePadding: isHovering ? 12 : 0
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(textTab)
                        .frame(width: 24, height: 24)
                        .background(
                            displayIsCloseHovering
                                ? (isActive
                                    ? tokens.fieldBackgroundHover
                                    : tokens.fieldBackground)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering && !freezesHoverState)
                .accessibilityHidden(!isHovering)
                .onHover { state in
                    guard !freezesHoverState else { return }
                    isCloseHovering = state
                }
                .accessibilityIdentifier("space-split-tab-close-\(tab.id.uuidString)")
                .sidebarAppKitPrimaryAction(isEnabled: isHovering && !freezesHoverState, action: onClose)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .onHover { hovering in
                guard !freezesHoverState else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering && !SidebarDragState.shared.isDragging
                }
            }
            .onChange(of: SidebarDragState.shared.isDragging) { _, isDragging in
                if isDragging {
                    isHovering = false
                }
            }
            .sidebarAppKitContextMenu(
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
                    onActivate: onActivate
                ),
                primaryAction: onActivate,
                sourceID: "space-split-tab-\(tab.id.uuidString)",
                entries: { contextMenuEntries }
            )
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
        .shadow(
            color: (isSplitActiveSide || isActive) ? tokens.sidebarSelectionShadow : .clear,
            radius: (isSplitActiveSide || isActive) ? 2 : 0,
            y: (isSplitActiveSide || isActive) ? 1 : 0
        )
    }

    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
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
        isHovering && !freezesHoverState
    }

    private var displayIsCloseHovering: Bool {
        isCloseHovering && !freezesHoverState
    }

}
