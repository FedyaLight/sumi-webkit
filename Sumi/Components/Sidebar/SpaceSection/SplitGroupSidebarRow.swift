import SwiftUI

enum SplitGroupSidebarItem: Identifiable {
    case tab(Tab)
    case pin(ShortcutPin)

    var id: UUID {
        switch self {
        case .tab(let tab):
            return tab.id
        case .pin(let pin):
            return pin.id
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .tab(let tab):
            return tab.name
        case .pin(let pin):
            return pin.preferredDisplayTitle
        }
    }

    var tab: Tab? {
        if case .tab(let tab) = self { return tab }
        return nil
    }

    var pin: ShortcutPin? {
        if case .pin(let pin) = self { return pin }
        return nil
    }
}

enum SplitGroupSidebarSegmentAction {
    case close
    case restore

    var systemImageName: String {
        switch self {
        case .close:
            return "xmark"
        case .restore:
            return "arrow.uturn.backward"
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .close:
            return "space-split-tab-close"
        case .restore:
            return "space-split-segment-restore"
        }
    }

    var help: String {
        switch self {
        case .close:
            return "Close split segment"
        case .restore:
            return "Return pinned tab to original place"
        }
    }
}

struct SplitGroupSidebarRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    let isAppKitInteractionEnabled: Bool
    let segmentAction: (SplitGroupSidebarItem) -> SplitGroupSidebarSegmentAction?
    var dragSource: (SplitGroupSidebarItem) -> SidebarDragSourceConfiguration? = { _ in nil }
    let contextMenuEntries: (Tab) -> [SidebarContextMenuEntry]
    let onActivate: (Tab) -> Void
    let onActivateGroup: () -> Void
    let onSegmentAction: (SplitGroupSidebarItem) -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SplitGroupSegment(
                    item: item,
                    spaceId: spaceId,
                    isActive: isActive(item),
                    segmentAction: segmentAction(item),
                    isAppKitInteractionEnabled: isAppKitInteractionEnabled,
                    dragSourceConfiguration: dragSource(item),
                    contextMenuEntries: {
                        item.tab.map(splitContextMenuEntries) ?? []
                    },
                    onActivate: { activate(item) },
                    onSegmentAction: { onSegmentAction(item) }
                )
                if index < items.count - 1 {
                    Rectangle()
                        .fill(tokens.separator.opacity(0.7))
                        .frame(width: 1, height: 22)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .padding(.horizontal, 2)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(8), style: .continuous)
                .fill(rowBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(8), style: .continuous))
        .sidebarDDGHover($isRowHovered, isEnabled: isRowHoverTrackingEnabled)
        .accessibilityIdentifier("space-split-group-\(group.id.uuidString)")
    }

    private func activate(_ item: SplitGroupSidebarItem) {
        if item.tab == nil {
            onActivateGroup()
            return
        }
        if let tab = item.tab {
            onActivate(tab)
        }
    }

    private var rowBackground: Color {
        if isFocusedGroup {
            return tokens.sidebarRowActive
        }
        if showsRowHoverBackground {
            return tokens.sidebarRowHover
        }
        return Color.clear
    }

    private var showsRowHoverBackground: Bool {
        guard !isFocusedGroup else { return false }
        return SidebarHoverChrome.displayHover(
            isRowHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var isRowHoverTrackingEnabled: Bool {
        !isFocusedGroup && isAppKitInteractionEnabled
    }

    private var isFocusedGroup: Bool {
        guard let currentTabId else { return false }
        return group.contains(currentTabId)
    }

    private var currentTabId: UUID? {
        browserManager.currentTab(for: windowState)?.id
    }

    private func isActive(_ item: SplitGroupSidebarItem) -> Bool {
        if currentTabId == item.id {
            return true
        }
        if let pin = item.pin {
            return windowState.currentShortcutPinId == pin.id
                || group.activeTabId == pin.id
                || group.member(forPinId: pin.id)?.tabId == currentTabId
        }
        if let tab = item.tab, let pinId = tab.shortcutPinId {
            return windowState.currentShortcutPinId == pinId
        }
        return false
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
    let item: SplitGroupSidebarItem
    let spaceId: UUID
    let isActive: Bool
    let segmentAction: SplitGroupSidebarSegmentAction?
    let isAppKitInteractionEnabled: Bool
    let dragSourceConfiguration: SidebarDragSourceConfiguration?
    let contextMenuEntries: () -> [SidebarContextMenuEntry]
    let onActivate: () -> Void
    let onSegmentAction: () -> Void

    @State private var isSegmentHoveredForActions = false
    @State private var isActionHovered = false
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                icon
                SumiTabTitleLabel(
                    title: item.title,
                    font: .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular),
                    textColor: tokens.primaryText,
                    trailingFadePadding: showsActionControls ? 2 : 0,
                    isLoading: item.tab?.isLoading ?? false
                )
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 7)
            .padding(.trailing, showsActionControls ? 28 : 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .sidebarDDGHover(
                $isSegmentHoveredForActions,
                isEnabled: segmentAction != nil && isAppKitInteractionEnabled
            )
            .sidebarAppKitContextMenu(
                isInteractionEnabled: (item.tab != nil || dragSourceConfiguration != nil) && isAppKitInteractionEnabled,
                dragSource: resolvedDragSourceConfiguration,
                primaryAction: onActivate,
                sourceID: rowSourceID,
                entries: contextMenuEntries
            )

            if let segmentAction {
                segmentActionButton(segmentAction)
                    .padding(.trailing, 4)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: item.tab?.url) {
            await item.tab?.fetchFaviconForVisiblePresentation()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let tab = item.tab {
            SidebarTabFaviconView(tab: tab, size: 16, cornerRadius: 4)
        } else if let pin = item.pin {
            pin.storedFavicon
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private var resolvedDragSourceConfiguration: SidebarDragSourceConfiguration? {
        if let dragSourceConfiguration {
            return dragSourceConfiguration
        }
        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
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
        )
    }

    private var rowSourceID: String {
        switch item {
        case .tab(let tab):
            return "space-split-tab-\(tab.id.uuidString)"
        case .pin(let pin):
            return "space-split-pin-\(pin.id.uuidString)"
        }
    }

    private var showsActionControls: Bool {
        guard segmentAction != nil else { return false }
        return SidebarHoverChrome.displayHover(
            isSegmentHoveredForActions,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private var displayIsActionHovering: Bool {
        SidebarHoverChrome.displayHover(
            isActionHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func segmentActionButton(_ action: SplitGroupSidebarSegmentAction) -> some View {
        Button(action: onSegmentAction) {
            Image(systemName: action.systemImageName)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tokens.primaryText)
                .frame(width: 20, height: 20)
                .background(displayIsActionHovering ? tokens.fieldBackgroundHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState
            )
        )
        .opacity(showsActionControls ? 1 : 0)
        .sidebarZenActionOpacity(showsActionControls)
        .allowsHitTesting(showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState)
        .sidebarDDGHover($isActionHovered, isEnabled: showsActionControls && isAppKitInteractionEnabled)
        .accessibilityIdentifier("\(action.accessibilityPrefix)-\(item.id.uuidString)")
        .help(action.help)
        .sidebarAppKitPrimaryAction(
            isEnabled: showsActionControls && !windowState.sidebarInteractionState.freezesSidebarHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: onSegmentAction
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
