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

enum SplitGroupSidebarModel {
    @MainActor
    static func items(for group: SplitGroup, tabManager: TabManager) -> [SplitGroupSidebarItem] {
        group.tabIds.compactMap { id in
            if let tab = tabManager.tab(for: id) {
                return .tab(tab)
            }
            if let pinId = group.member(for: id)?.pinId,
               let pin = tabManager.shortcutPin(by: pinId) {
                return .pin(pin)
            }
            if let pin = tabManager.shortcutPin(by: id) {
                return .pin(pin)
            }
            return nil
        }
    }

    @MainActor
    static func member(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupMember? {
        if let pin = item.pin {
            return group.member(forPinId: pin.id) ?? group.member(for: pin.id)
        }
        if let tab = item.tab {
            if let pinId = tab.shortcutPinId {
                return group.member(forPinId: pinId) ?? group.member(for: tab.id)
            }
            return group.member(for: tab.id)
        }
        return nil
    }

    @MainActor
    static func segmentAction(
        for item: SplitGroupSidebarItem,
        in group: SplitGroup
    ) -> SplitGroupSidebarSegmentAction? {
        if member(for: item, in: group)?.isShortcutBacked == true {
            return .restore
        }
        return item.tab == nil ? nil : .close
    }

    @MainActor
    static func shortcutPin(
        for item: SplitGroupSidebarItem,
        member: SplitGroupMember?,
        tabManager: TabManager
    ) -> ShortcutPin? {
        if let pin = item.pin {
            return pin
        }
        if let pinId = item.tab?.shortcutPinId ?? member?.pinId {
            return tabManager.shortcutPin(by: pinId)
        }
        return nil
    }

    static func sourceZone(for pin: ShortcutPin, fallbackSpaceId: UUID) -> DropZoneID {
        switch pin.role {
        case .essential:
            return .essentials
        case .spacePinned:
            if let folderId = pin.folderId {
                return .folder(folderId)
            }
            return .spacePinned(pin.spaceId ?? fallbackSpaceId)
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
    var onSegmentActionAnimationStart: (SplitGroupSidebarItem) -> Void = { _ in }
    let onSegmentAction: (SplitGroupSidebarItem) -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false
    @State private var displayedItems: [SplitGroupSidebarItem] = []
    @State private var departingItemIds = Set<UUID>()
    @State private var isCollapsingRow = false

    var body: some View {
        GeometryReader { geometry in
            let rowItems = resolvedDisplayItems
            let activeCount = max(rowItems.filter { !isDeparting($0) }.count, 1)
            let separatorCount = max(activeCount - 1, 0)
            let segmentWidth = max(
                0,
                (geometry.size.width - CGFloat(separatorCount)) / CGFloat(activeCount)
            )

            HStack(spacing: 0) {
                ForEach(Array(rowItems.enumerated()), id: \.element.id) { index, item in
                    SplitGroupSegment(
                        item: item,
                        spaceId: spaceId,
                        isActive: isActive(item),
                        isDeparting: isDeparting(item),
                        segmentAction: segmentAction(item),
                        isAppKitInteractionEnabled: isAppKitInteractionEnabled && !isDeparting(item),
                        dragSourceConfiguration: dragSource(item),
                        contextMenuEntries: {
                            item.tab.map(splitContextMenuEntries) ?? []
                        },
                        onActivate: { activate(item) },
                        onSegmentAction: { performSegmentMutation(for: item, in: rowItems) }
                    )
                    .frame(width: isDeparting(item) ? 0 : segmentWidth)
                    .clipped()

                    if shouldShowSeparator(after: index, in: rowItems) {
                        Rectangle()
                            .fill(tokens.separator.opacity(0.7))
                            .frame(width: 1, height: 22)
                            .padding(.vertical, 6)
                    }
                }
            }
            .animation(
                shouldAnimateProjectedLayout ? SidebarDropMotion.contentLayout : nil,
                value: displayedItems.map(\.id)
            )
            .animation(
                shouldAnimateProjectedLayout ? SidebarDropMotion.contentLayout : nil,
                value: departingItemIds.map(\.uuidString).sorted()
            )
        }
        .sidebarRowLifecycle(isCollapsed: isCollapsingRow)
        .padding(.horizontal, 2)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: rowBackground,
            cornerRadius: sumiSettings.resolvedCornerRadius(8),
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: isFocusedGroup
        )
        .sidebarDDGHover($isRowHovered, isEnabled: isRowHoverTrackingEnabled)
        .accessibilityIdentifier("space-split-group-\(group.id.uuidString)")
        .onAppear {
            if displayedItems.isEmpty {
                displayedItems = items
            }
        }
        .onChange(of: items.map(\.id)) { _, _ in
            reconcileDisplayedItems(with: items)
        }
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

    private var drawsRowSurface: Bool {
        isFocusedGroup || showsRowHoverBackground
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
                performSplitSidebarMutation {
                    splitManager.unsplitActiveGroup(for: windowState.id)
                }
            }))
        ]
        entries.append(.separator)
        entries.append(contentsOf: splitEntries)
        return entries
    }

    private func performSplitSidebarMutation(_ update: () -> Void) {
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            update()
            return
        }
        withAnimation(SidebarDropMotion.contentLayout, update)
    }

    private var shouldAnimateProjectedLayout: Bool {
        !reduceMotion && !sumiSettings.shouldReduceChromeMotion
    }

    private var resolvedDisplayItems: [SplitGroupSidebarItem] {
        displayedItems.isEmpty ? items : displayedItems
    }

    private func isDeparting(_ item: SplitGroupSidebarItem) -> Bool {
        departingItemIds.contains(item.id)
    }

    private func shouldShowSeparator(after index: Int, in rowItems: [SplitGroupSidebarItem]) -> Bool {
        guard index < rowItems.count - 1 else { return false }
        guard !isDeparting(rowItems[index]) else { return false }
        return rowItems[(index + 1)...].contains { !isDeparting($0) }
    }

    private func performSegmentMutation(for item: SplitGroupSidebarItem, in rowItems: [SplitGroupSidebarItem]) {
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            onSegmentAction(item)
            return
        }

        onSegmentActionAnimationStart(item)
        withAnimation(SidebarDropMotion.contentLayout) {
            _ = departingItemIds.insert(item.id)
            if shouldCollapseRowAfterRemoving(item, from: rowItems) {
                isCollapsingRow = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + segmentActionCompletionDelay(for: item)) {
            onSegmentAction(item)
        }
    }

    private func segmentActionCompletionDelay(for item: SplitGroupSidebarItem) -> Double {
        segmentAction(item) == .restore
            ? SidebarDropMotion.shortcutRestoreActionDelay
            : SidebarDropMotion.contentLayoutDuration
    }

    private func shouldCollapseRowAfterRemoving(
        _ item: SplitGroupSidebarItem,
        from rowItems: [SplitGroupSidebarItem]
    ) -> Bool {
        guard !group.isShortcutHosted,
              segmentAction(item) == .close
        else {
            return false
        }

        let activeItems = rowItems.filter { !isDeparting($0) }
        guard activeItems.count <= SplitGroup.minimumTabs else {
            return false
        }

        let remainingItems = activeItems.filter { $0.id != item.id }
        return remainingItems.count == 1 && isShortcutBacked(remainingItems[0])
    }

    private func isShortcutBacked(_ item: SplitGroupSidebarItem) -> Bool {
        switch item {
        case .pin(let pin):
            return group.member(forPinId: pin.id)?.isShortcutBacked == true
                || group.member(for: pin.id)?.isShortcutBacked == true
        case .tab(let tab):
            if let pinId = tab.shortcutPinId,
               group.member(forPinId: pinId)?.isShortcutBacked == true {
                return true
            }
            return group.member(for: tab.id)?.isShortcutBacked == true
        }
    }

    private func reconcileDisplayedItems(with newItems: [SplitGroupSidebarItem]) {
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            displayedItems = newItems
            departingItemIds.removeAll()
            return
        }

        let oldItems = displayedItems.isEmpty ? items : displayedItems
        let newItemsById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        let newIds = Set(newItems.map(\.id))
        let removedIds = Set(oldItems.map(\.id)).subtracting(newIds)

        guard !removedIds.isEmpty else {
            withAnimation(SidebarDropMotion.contentLayout) {
                displayedItems = newItems
                departingItemIds.formIntersection(newIds)
            }
            return
        }

        if removedIds.isSubset(of: departingItemIds) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedItems = newItems
                departingItemIds.subtract(removedIds)
            }
            return
        }

        var seenIds = Set<UUID>()
        var projectedItems: [SplitGroupSidebarItem] = oldItems.map { oldItem in
            seenIds.insert(oldItem.id)
            return newItemsById[oldItem.id] ?? oldItem
        }
        projectedItems.append(contentsOf: newItems.filter { seenIds.insert($0.id).inserted })

        withAnimation(SidebarDropMotion.contentLayout) {
            displayedItems = projectedItems
            departingItemIds.formUnion(removedIds)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) {
            displayedItems = newItems
            departingItemIds.subtract(removedIds)
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

private struct SplitGroupSegment: View {
    let item: SplitGroupSidebarItem
    let spaceId: UUID
    let isActive: Bool
    let isDeparting: Bool
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
        .opacity(isDeparting ? 0 : 1)
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
        Button(action: performSegmentAction) {
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
            action: performSegmentAction
        )
    }

    private func performSegmentAction() {
        guard !isDeparting else { return }
        onSegmentAction()
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
